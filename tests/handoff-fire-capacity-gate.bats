#!/usr/bin/env bats
# handoff-fire.sh — P0-17 machine-capacity admission gate (lag incident 2026-07-29).
#
# WHY THIS EXISTS: every admission guard in the fleet counted API QUOTA — cc-wave-plan's
# CC_WAVE_MAX_PER_ACCT (accounts x 2), cc-dispatch's CC_DISPATCH_MAX_SPAWN, the Fable window — and
# NOTHING counted the cores the spawned sessions actually run on. Measured 2026-07-29: 33 live
# Opus-max sessions across 38 panes on a 10-core box, load 27 (2.72/core), 8% idle. Quota headroom
# existed throughout, so no existing gate had any reason to fire.
#
# handoff-fire.sh is the universal spawn chokepoint (cc-dispatch defaults CC_DISPATCH_SPAWN_BIN to
# it; the desk, the ground-up coordinator and manual fires all call it), so the hardware term binds
# here or nowhere.
#
# sysctl is STUBBED on PATH so load/core count are inputs, not ambient facts — otherwise every
# assertion below would flip with the mood of the machine running the suite. Each case runs
# --dry-run so an ADMIT verdict never actually fires a session.
#
# RED-PROOF (recorded 2026-07-29): case 1 was replayed against the pristine pre-change
# scripts/handoff-fire.sh recovered via `git archive origin/main` (2595 lines, 0 occurrences of
# capacity_gate) and exited 0, not 9 — so the exit-9 assertions below are caused BY the gate and
# not by some pre-existing refusal path.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  # HERMETICITY: handoff-fire.sh resolves the registry, mailbox, roles and projects dirs under
  # $HOME. Fixture it so an ADMIT case — which proceeds PAST the gate into that machinery — can
  # never read or mutate the operator's live ~/. Must precede any invocation below.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN"
  # stub sysctl: hw.ncpu -> $STUB_NCPU, vm.loadavg -> the 3-field "{ a b c }" macOS shape
  cat > "$BIN/sysctl" <<'EOF'
#!/bin/bash
case "$*" in
  *hw.ncpu*)    echo "${STUB_NCPU:-10}" ;;
  *vm.loadavg*) echo "{ ${STUB_LOAD:-1.00} ${STUB_LOAD:-1.00} ${STUB_LOAD:-1.00} }" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$BIN/sysctl"
  PAYLOAD="$BATS_TEST_TMPDIR/p.txt"
  echo "TASK — capacity gate fixture payload." > "$PAYLOAD"
  export PATH="$BIN:$PATH"
  # M10: the gate grew a SECOND term (memory headroom). Pin it to a comfortably-admitting synthetic
  # value here so cases 1–9 keep asserting the LOAD term alone and never flip with the free-memory
  # mood of the machine — the same ambient-dependence M11 removes from the rest of the corpus. The
  # headroom cases below override this per-test; the parse cases unset it and stub vm_stat instead.
  export CC_FIRE_HEADROOM_OVERRIDE=64
}

# fire() runs the real script with the stub sysctl in front; all cases are --dry-run.
fire() { run env STUB_NCPU="$1" STUB_LOAD="$2" bash "$HF" --prompt-file "$PAYLOAD" --dry-run "${@:3}"; }

# fire_h() — an idle box (load term always admits) so the HEADROOM term is the only thing under
# test. $1 = the CC_FIRE_HEADROOM_OVERRIDE value; remaining args are passed to the script.
fire_h() { run env STUB_NCPU=10 STUB_LOAD=1.00 CC_FIRE_HEADROOM_OVERRIDE="$1" \
                bash "$HF" --prompt-file "$PAYLOAD" --dry-run "${@:2}"; }

# vmstub() writes a synthetic vm_stat onto PATH. $1 = page size advertised in its OWN header,
# $2..$5 = free / speculative / inactive / purgeable page counts. It also emits large `Pages active`,
# `Pages wired down` and `Pages purged` rows: those are NOT reclaimable (purged is a lifetime
# counter, not a population) and a parser that sums them would blow every expected number below.
vmstub() {
  cat > "$BIN/vm_stat" <<EOF
#!/bin/bash
echo "Mach Virtual Memory Statistics: (page size of $1 bytes)"
echo "Pages free:                              $2."
echo "Pages active:                           9999999."
echo "Pages inactive:                          $4."
echo "Pages speculative:                       $3."
echo "Pages throttled:                              0."
echo "Pages wired down:                       8888888."
echo "Pages purgeable:                         $5."
echo "\"Translation faults\":               10498751028."
echo "Pages purged:                           7777777."
EOF
  chmod +x "$BIN/vm_stat"
}

@test "1 saturated box (2.72/core > 2.0 ceiling) -> REFUSE with exit 9 and the measured numbers" {
  fire 10 27.16
  [ "$status" -eq 9 ]
  echo "$output" | grep -q 'capacity gate: REFUSING a net-new fire' || false
  # a refusal with no numbers is unauditable — assert the load, the cores and the ratio are all shown
  echo "$output" | grep -q 'load 27.16 on 10 cores = 2.72/core' || false
  echo "$output" | grep -q 'ceiling 2.0/core' || false
}

@test "2 POSITIVE CONTROL — idle box (0.50/core) -> ADMIT, never exit 9" {
  fire 10 5.00
  [ "$status" -ne 9 ]
  echo "$output" | grep -q 'capacity gate: ADMIT' || false
}

@test "3 kill switch CC_FIRE_CAPACITY_GATE=off -> admits even a saturated box" {
  run env STUB_NCPU=10 STUB_LOAD=27.16 CC_FIRE_CAPACITY_GATE=off \
      bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -ne 9 ]
  # gate is fully silent when off — no verdict line at all
  run bash -c "env STUB_NCPU=10 STUB_LOAD=27.16 CC_FIRE_CAPACITY_GATE=off bash '$HF' --prompt-file '$PAYLOAD' --dry-run 2>&1 | grep -c 'capacity gate' || true"
  [ "$output" = "0" ]
}

@test "4 ceiling is tunable — CC_FIRE_MAX_LOAD_PER_CORE=3.0 admits 2.72/core" {
  run env STUB_NCPU=10 STUB_LOAD=27.16 CC_FIRE_MAX_LOAD_PER_CORE=3.0 \
      bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -ne 9 ]
  echo "$output" | grep -q 'capacity gate: ADMIT' || false
}

@test "5 --recycle is EXEMPT — a replacement fire is net-zero panes and must never be gated" {
  # Gating a recycle would strand the very handoff that SHEDS load (fail-closed-as-amplifier).
  fire 10 27.16 --recycle
  [ "$status" -ne 9 ]
}

@test "6 FAIL-OPEN — unreadable hw.ncpu admits rather than stranding the fleet" {
  cat > "$BIN/sysctl" <<'EOF'
#!/bin/bash
echo "garbage"
EOF
  chmod +x "$BIN/sysctl"
  run bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -ne 9 ]
  echo "$output" | grep -q "hw.ncpu unreadable" || false
  echo "$output" | grep -q "ADMIT (fail-open)" || false
}

@test "7 FAIL-OPEN — unreadable vm.loadavg admits (probe death is never a refusal)" {
  cat > "$BIN/sysctl" <<'EOF'
#!/bin/bash
case "$*" in
  *hw.ncpu*)    echo "10" ;;
  *vm.loadavg*) echo "{ }" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$BIN/sysctl"
  run bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -ne 9 ]
  echo "$output" | grep -q "vm.loadavg unreadable" || false
}

@test "8 a bad ceiling value fails OPEN, never wedges every fire shut" {
  run env STUB_NCPU=10 STUB_LOAD=27.16 CC_FIRE_MAX_LOAD_PER_CORE=abc \
      bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -ne 9 ]
  echo "$output" | grep -q 'bad CC_FIRE_MAX_LOAD_PER_CORE' || false
}

@test "9 the gate runs BEFORE any side effect — a refused fire spawns nothing" {
  # exit 9 must happen in the pre-side-effect guard block, beside the /goal-cap and empty-payload
  # refusals. Proven positionally: the gate call sits after check_slash_head and before it2 land.
  run bash -c "grep -n 'capacity_gate || exit 9' '$HF' | cut -d: -f1"
  gate_line="$output"
  run bash -c "grep -n 'check_slash_head  \"\$PROMPT_FILE\"' '$HF' | cut -d: -f1"
  slash_line="$output"
  [ "$gate_line" -gt "$slash_line" ]
  # and it precedes the spawn machinery
  run bash -c "grep -n '^spawn()' '$HF' | cut -d: -f1"
  spawn_line="$output"
  [ "$gate_line" -lt "$spawn_line" ]
}

# ================================================================================================
# M10 (MACHINE_CAPACITY_V2 §11.3) — the memory-headroom admission term.
#
# WHY A SECOND TERM: loadavg is box-wide, so it is neither session-ATTRIBUTABLE nor SHEDDABLE. On
# 2026-07-29 the gate above refused every net-new fire at 5.20/core with only 12–15 sessions live,
# while ~2.0 of those cores were iTerm2+WindowServer merely DRAWING panes — closing a session would
# not have moved the number the gate reads. Memory headroom is both attributable and sheddable, so
# it is the term that can actually be acted on. The load ceiling STAYS (§9.5 measured it behaving as
# a ceiling); the terms are additive and ordered, load first.
#
# RED-PROOF (recorded 2026-07-30): the whole suite was replayed against the pristine pre-change tree
# recovered via `git archive eaa0cdeb` (3558 lines, 0 occurrences of CC_FIRE_MIN_HEADROOM_GB), run
# from that tree's OWN root so REPO/HF/the pin-guard's reads all resolve pre-change — one tree per
# side, never a mix. 13 of 24 went RED there, each at the exact point it asserts: the REFUSE cases
# exited 0 instead of 9 (case 10 failed on `[ "$status" -eq 9 ]`), the ADMIT cases found no headroom
# line, and the PIN-GUARD named tests/handoff-fire-focus.bats as unpinned. 0 skips either side, so
# nothing passed vacuously.
#
# The two new cases that stay GREEN on the pristine tree are green BY DESIGN, and would be defects
# otherwise: case 22 asserts the PRE-EXISTING --recycle exemption, which M10 must not disturb, and
# case 24 is the pin-guard predicate's own positive control over fixtures it writes itself — a
# control that only passes after the change is not a control. Cases 1–9 stay green because M10 is
# purely additive to the load term.
# ================================================================================================

@test "10 M10 headroom below the floor -> REFUSE with exit 9 and the measured numbers" {
  fire_h 1.50
  [ "$status" -eq 9 ]
  echo "$output" | grep -q 'REFUSING a net-new fire — reclaimable memory headroom 1.50GB < floor 4GB' || false
  # the load term admitted FIRST and printed its own numbers, so the refusal stays attributable to
  # one term — a refusal with no numbers is unauditable, and one with ambiguous numbers is worse
  echo "$output" | grep -q 'capacity gate: ADMIT — load 1.00' || false
}

@test "11 POSITIVE CONTROL — headroom above the floor -> ADMIT, never exit 9" {
  fire_h 12.00
  [ "$status" -ne 9 ]
  echo "$output" | grep -q 'headroom ADMIT — reclaimable 12.00GB (floor 4GB)' || false
}

@test "12 the floor is tunable — CC_FIRE_MIN_HEADROOM_GB=1 admits 1.50GB" {
  run env STUB_NCPU=10 STUB_LOAD=1.00 CC_FIRE_HEADROOM_OVERRIDE=1.50 CC_FIRE_MIN_HEADROOM_GB=1 \
      bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -ne 9 ]
  echo "$output" | grep -q 'headroom ADMIT — reclaimable 1.50GB (floor 1GB)' || false
}

@test "13 ORDER — the load term refuses FIRST; a doubly-saturated box reports load, not headroom" {
  run env STUB_NCPU=10 STUB_LOAD=27.16 CC_FIRE_HEADROOM_OVERRIDE=0.10 \
      bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -eq 9 ]
  echo "$output" | grep -q 'REFUSING a net-new fire — load 27.16' || false
  # the headroom term must not run at all: two reasons for one refusal is an unreadable telemetry row
  run bash -c "env STUB_NCPU=10 STUB_LOAD=27.16 CC_FIRE_HEADROOM_OVERRIDE=0.10 bash '$HF' --prompt-file '$PAYLOAD' --dry-run 2>&1 | grep -c 'headroom' || true"
  [ "$output" = "0" ]
  # NOT VACUOUS: a tree with no headroom term at all would satisfy both assertions above. So prove
  # the term exists and is reachable — the IDENTICAL headroom value refuses once load admits. Only
  # then is the silence above an ORDERING fact rather than an absence.
  fire_h 0.10
  [ "$status" -eq 9 ]
  echo "$output" | grep -q 'reclaimable memory headroom 0.10GB' || false
}

@test "14 kill switch CC_FIRE_HEADROOM_GATE=off -> admits despite headroom far under the floor" {
  run env STUB_NCPU=10 STUB_LOAD=1.00 CC_FIRE_HEADROOM_OVERRIDE=0.10 CC_FIRE_HEADROOM_GATE=off \
      bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -ne 9 ]
  # it disables ONLY its own term — the load term still measures and still reports
  echo "$output" | grep -q 'capacity gate: ADMIT — load' || false
  run bash -c "env STUB_NCPU=10 STUB_LOAD=1.00 CC_FIRE_HEADROOM_OVERRIDE=0.10 CC_FIRE_HEADROOM_GATE=off bash '$HF' --prompt-file '$PAYLOAD' --dry-run 2>&1 | grep -c 'headroom' || true"
  [ "$output" = "0" ]
  # NOT VACUOUS: a tree with no headroom term would admit and print nothing here too. The switch is
  # only proven to be a SWITCH if the identical value refuses with the switch absent.
  fire_h 0.10
  [ "$status" -eq 9 ]
}

@test "15 FAIL-OPEN — a non-numeric headroom reading admits rather than stranding the fleet" {
  fire_h abc
  [ "$status" -ne 9 ]
  echo "$output" | grep -q "reclaimable headroom unreadable ('abc')" || false
  echo "$output" | grep -q "ADMIT (fail-open)" || false
}

@test "16 a bad floor value fails OPEN, never wedges every fire shut" {
  run env STUB_NCPU=10 STUB_LOAD=1.00 CC_FIRE_HEADROOM_OVERRIDE=1.50 CC_FIRE_MIN_HEADROOM_GB=lots \
      bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -ne 9 ]
  echo "$output" | grep -q "bad CC_FIRE_MIN_HEADROOM_GB ('lots')" || false
}

@test "17 page size comes from vm_stat's OWN header — 524288 pages is 8.00GB at 16384 bytes" {
  vmstub 16384 524288 0 0 0
  run env STUB_NCPU=10 STUB_LOAD=1.00 CC_FIRE_HEADROOM_OVERRIDE= \
      bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -ne 9 ]
  echo "$output" | grep -q 'headroom ADMIT — reclaimable 8.00GB' || false
}

@test "18 SAME page counts, 4096-byte header -> 2.00GB and a REFUSE (the size is READ, not assumed)" {
  # The pair 17/18 is the whole point: hardcoding 4096 would understate a healthy Apple-silicon box
  # 4x and refuse every fire. Only a parser that reads the header can produce both numbers.
  vmstub 4096 524288 0 0 0
  run env STUB_NCPU=10 STUB_LOAD=1.00 CC_FIRE_HEADROOM_OVERRIDE= \
      bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -eq 9 ]
  echo "$output" | grep -q 'reclaimable memory headroom 2.00GB' || false
}

@test "19 headroom sums exactly free+speculative+inactive+purgeable — active/wired/purged excluded" {
  # 4 x 131072 pages x 16384 B = 8.00 GB exactly. vmstub also emits active=9999999 and wired=8888888
  # (~288 GB if summed) plus `Pages purged`, which is a LIFETIME COUNTER and not a population at all.
  vmstub 16384 131072 131072 131072 131072
  run env STUB_NCPU=10 STUB_LOAD=1.00 CC_FIRE_HEADROOM_OVERRIDE= \
      bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -ne 9 ]
  echo "$output" | grep -q 'headroom ADMIT — reclaimable 8.00GB' || false
}

@test "20 FAIL-OPEN — an unreadable vm_stat admits (probe death is never a refusal)" {
  printf '#!/bin/bash\necho garbage\n' > "$BIN/vm_stat"
  chmod +x "$BIN/vm_stat"
  run env STUB_NCPU=10 STUB_LOAD=1.00 CC_FIRE_HEADROOM_OVERRIDE= \
      bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -ne 9 ]
  echo "$output" | grep -q "reclaimable headroom unreadable" || false
  echo "$output" | grep -q "ADMIT (fail-open)" || false
}

@test "21 BOTH refusal reasons reach emit_fire_refusal — the fire that did NOT happen is logged" {
  # emit_fire_refusal (handoff-fire.sh:267) -> emit_fire_event -> one jsonl row per refusal. Without
  # it a gate-blocked fleet reads exactly like a quiet one in handoffs.jsonl, which is the
  # absence-alarm-needs-existence-evidence shape. The headroom term must not be the silent one.
  command -v jq >/dev/null 2>&1 || skip "emit_fire_event writes rows only when jq is present"
  LOG="$HOME/.claude/logs/handoffs.jsonl"
  fire 10 27.16
  [ "$status" -eq 9 ]
  fire_h 1.50
  [ "$status" -eq 9 ]
  run bash -c "jq -r 'select(.class==\"refused\") | .refuse_reason' '$LOG'"
  echo "$output" | grep -qx 'capacity' || false
  echo "$output" | grep -qx 'headroom' || false
  # and the detail carries the numbers, so the row is actionable without re-running the fire
  run bash -c "jq -r 'select(.refuse_reason==\"headroom\") | .detail' '$LOG'"
  [ "$output" = "reclaimable 1.50GB < floor 4GB" ]
}

@test "22 --recycle is EXEMPT from BOTH terms — a replacement fire is net-zero panes AND net-zero memory" {
  # Gating a recycle would strand the very handoff that SHEDS the memory (fail-closed-as-amplifier);
  # the headroom term inherits that exemption from the call site, so it is asserted, not assumed.
  run env STUB_NCPU=10 STUB_LOAD=27.16 CC_FIRE_HEADROOM_OVERRIDE=0.10 \
      bash "$HF" --prompt-file "$PAYLOAD" --dry-run --recycle
  [ "$status" -ne 9 ]
}

# _setup_pins <file> — 0 when that file's setup() block exports BOTH gate kill switches.
_setup_pins() {
  local blk
  blk="$(awk '/setup\(\)[[:space:]]*\{/{p=1} p{print} p&&/^\}/{exit}' "$1")"
  printf '%s\n' "$blk" | grep -q 'export CC_FIRE_CAPACITY_GATE=off' || return 1
  printf '%s\n' "$blk" | grep -q 'export CC_FIRE_HEADROOM_GATE=off'  || return 1
  return 0
}

@test "23 PIN-GUARD (M11) — the known red-by-load fire suites pin BOTH terms off in setup()" {
  # 16 corpus tests were RED on a PRISTINE tree purely because the box was busy (map R-1) — a gate
  # failing its own suite and blocking deploy verification. The remedy is a STANDING property of the
  # corpus, not a one-time edit, so it gets a guard: a new fire suite, or a setup() rewrite that
  # drops the pin, goes RED here instead of quietly making the machine's mood a test input.
  #
  # 2026-07-31 — the "a new fire suite goes RED here" half of that promise was FALSE, and this
  # roster is why. A hardcoded list cannot notice a suite it does not name: fire-autonomy.bats and
  # notify-back.bats both reach the real fire path, neither was listed, and at load 41.72 on 10
  # cores they went RED on a PRISTINE tree (4 and 8 tests, exit 9) — blocking every land in the
  # repo, including diffs nowhere near handoff-fire. The guard stayed green throughout, because it
  # was only ever asserting that THESE THREE files kept their pins. Enumerating examples cannot
  # express the class. Both are added below, but the roster is a FLOOR — test 25 derives the real
  # population from the corpus so the next unlisted fire suite cannot repeat this.
  local f rc
  for f in handoff-fire-focus.bats handoff-fire-payload-lint.bats fire-engagement.bats \
           fire-autonomy.bats notify-back.bats; do
    rc=0; _setup_pins "$REPO/tests/$f" || rc=$?
    [ "$rc" -eq 0 ] || { echo "UNPINNED: tests/$f setup() is missing a gate export"; false; }
  done
  # DISJOINTNESS: this suite must NOT be pinned off, or the gate would be exercised nowhere at all
  # — "pin it everywhere" is the failure mode that turns M11 into a deletion of the M10 gate.
  rc=0; _setup_pins "$BATS_TEST_FILENAME" || rc=$?
  [ "$rc" -ne 0 ] || false
}

@test "24 PIN-GUARD POSITIVE CONTROL — the guard's predicate FAILS on an unpinned setup()" {
  # Without this, test 23 could be passing because the predicate cannot fail (a check that cannot
  # go red is a deleted check). Both a bare setup() and a HALF-pinned one must be rejected.
  local rc
  printf '#!/usr/bin/env bats\nsetup() {\n  REPO=x\n}\n@test "t" { true; }\n' \
    > "$BATS_TEST_TMPDIR/unpinned.bats"
  rc=0; _setup_pins "$BATS_TEST_TMPDIR/unpinned.bats" || rc=$?
  [ "$rc" -ne 0 ] || false
  printf '#!/usr/bin/env bats\nsetup() {\n  export CC_FIRE_CAPACITY_GATE=off\n}\n@test "t" { true; }\n' \
    > "$BATS_TEST_TMPDIR/half.bats"
  rc=0; _setup_pins "$BATS_TEST_TMPDIR/half.bats" || rc=$?
  [ "$rc" -ne 0 ] || false
  # ...and PASSES on a fully pinned one, so the predicate is not simply always-false
  printf '#!/usr/bin/env bats\nsetup() {\n  export CC_FIRE_CAPACITY_GATE=off\n  export CC_FIRE_HEADROOM_GATE=off\n}\n@test "t" { true; }\n' \
    > "$BATS_TEST_TMPDIR/pinned.bats"
  rc=0; _setup_pins "$BATS_TEST_TMPDIR/pinned.bats" || rc=$?
  [ "$rc" -eq 0 ] || false
}

# _fires <file> — 0 when that file EXECUTES handoff-fire (command position), not merely
# mentions the path. The distinction is load-bearing: the source lints (self-path-lint,
# test-hermeticity-lint, iterm2-appname-lint) all name handoff-fire.sh while never running
# it, and sweeping them in would demand pins on suites the gate can never reach.
_fires() {
  grep -qE '(^|[[:space:];|&])(bash|run bash|env [^|;]*bash)[[:space:]]+"\$\{?HF\}?"' "$1"
}

@test "25 PIN-GUARD is DERIVED — no NEW unpinned fire suite may appear (ratchet)" {
  # Test 23's roster is a list of names, so it can only ever re-check files someone already
  # thought of — which is exactly how fire-autonomy + notify-back reached trunk unpinned and
  # blocked every land. This derives the population instead: every suite that EXECUTES the
  # fire must be pinned, or be named below as grandfathered. New arrivals go RED here.
  #
  # The grandfathered set is NOT an endorsement — those 11 execute the fire and are unpinned,
  # so they are load-sensitive on paper. They are held rather than blanket-pinned because
  # blanket-pinning is the M11 failure mode test 23's DISJOINTNESS clause warns about, and
  # because none of them has been OBSERVED red (they are not in the smoke's direct set). Pin
  # one the moment it is measured red; never widen the list. Tracked as task #112.
  local grandfathered=" desk-land.bats handoff-fire-account-sweep.bats
    handoff-fire-completion-push.bats handoff-fire-failed-cleanup.bats
    handoff-fire-validate.bats handoff-orphaned-assignee.bats
    handoff-recycle-durable-cwd.bats handoff-recycle-engagement.bats
    handoff-selfclose-session-pin.bats handoff-selfclose-teammate-gate.bats
    handoff-selfclose.bats "
  # Collapse the literal's newlines/indent to single spaces BEFORE the membership test.
  # `case *" $b "*` needs a space on BOTH sides, and a name that lands at end-of-line is
  # followed by a newline — so the wrapped entries silently missed and reported as NEW.
  # Caught here by exactly the 5 line-final names; the delimiter must not depend on how
  # the list happens to be wrapped.
  grandfathered=" $(printf '%s' "$grandfathered" | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//') "
  local f b nnew=0 nfire=0
  for f in "$REPO"/tests/*.bats; do
    b="$(basename "$f")"
    _fires "$f" || continue
    nfire=$((nfire+1))
    # this suite is disjoint BY DESIGN (test 23) — pinning it would delete the gate's coverage
    [ "$b" = "$(basename "$BATS_TEST_FILENAME")" ] && continue
    case "$grandfathered" in *" $b "*) continue ;; esac
    if ! _setup_pins "$f"; then
      echo "NEW UNPINNED FIRE SUITE: tests/$b — add the two M11 exports to its setup()"
      nnew=$((nnew+1))
    fi
  done
  echo "pin-guard: $nfire fire-executing suite(s); 11 grandfathered; $nnew new unpinned"
  # the population must be non-trivial, else this ratchet passes by finding nothing at all
  [ "$nfire" -ge 10 ] || { echo "derivation found only $nfire suites — predicate broke"; false; }
  # ...and the hold-list must not have rotted into a wildcard. Every grandfathered name must
  # still name a REAL suite: an entry that no longer exists is a silent exemption, and the
  # normalization above is exactly the kind of edit that could widen the match to everything.
  local g ng=0
  for g in $grandfathered; do
    [ -f "$REPO/tests/$g" ] || { echo "STALE grandfather entry: $g no longer exists — drop it"; false; }
    ng=$((ng+1))
  done
  [ "$ng" -eq 11 ] || { echo "grandfathered count drifted: $ng (expected 11) — the hold-list may only SHRINK"; false; }
  [ "$nnew" -eq 0 ] || false
}

@test "26 DERIVATION POSITIVE CONTROL — _fires separates executing from merely mentioning" {
  # Without this, test 25 could be green because _fires matches nothing (an empty population
  # ratchets nothing). Assert both directions on synthetic files.
  printf '@test "t" { run bash "$HF" --dry-run; }\n'      > "$BATS_TEST_TMPDIR/exec.bats"
  _fires "$BATS_TEST_TMPDIR/exec.bats" || { echo "_fires MISSED a real execution"; false; }
  printf 'grep -n handoff-fire.sh "$REPO/scripts/handoff-fire.sh"\n' > "$BATS_TEST_TMPDIR/mention.bats"
  ! _fires "$BATS_TEST_TMPDIR/mention.bats" || { echo "_fires matched a mere MENTION"; false; }
  # and the two suites this change pinned must be inside the derived population, not outside it
  # (if _fires missed them, test 25 would be green for the wrong reason — the original defect)
  _fires "$REPO/tests/fire-autonomy.bats" || { echo "_fires misses fire-autonomy"; false; }
  _fires "$REPO/tests/notify-back.bats"   || { echo "_fires misses notify-back"; false; }

  # MEMBERSHIP CONTROL — test 25 normalizes its hold-list's whitespace, and a normalization
  # that over-reaches (e.g. collapsing to a bare `*`) would grandfather the whole corpus and
  # make the ratchet vacuously green. Assert the predicate still SEPARATES: a real member
  # matches, an invented name does not.
  local gl=" desk-land.bats handoff-selfclose.bats "
  case "$gl" in *" desk-land.bats "*) : ;; *) echo "membership REJECTED a real member"; false ;; esac
  case "$gl" in *" not-a-real-suite.bats "*) echo "membership ACCEPTED a non-member"; false ;; esac
}

# ---- ADMIT-SIDE TELEMETRY (2026-07-31) --------------------------------------------------------
# Test 21 proved the REFUSALS are recorded. Nothing recorded the ADMITS, so the durable record could
# only ever answer "how often did it refuse?" — and the admit/refuse RATIO, the quantity every claim
# about this gate actually rests on, was unprovable from disk. MACHINE_CAPACITY_V2 §9.5 is the
# receipt: this gate was called a "permanent dispatch outage" on 13 refusal samples and retracted.
#
# RED-PROOF (recorded 2026-07-31, and re-runnable): cases 25-30 were replayed against the pristine
# pre-change scripts/handoff-fire.sh from `git show HEAD:scripts/handoff-fire.sh` — 25/26/27/28/29
# FAIL there (no `admitted` row exists to select) and 30 FAILS (no `gate` field on the refusals), so
# every assertion below is caused BY the change. Case 31 is a source lint and passes on both trees
# only because the old tree has no emit sites to miss; its positive control is inline.

@test "25 ADMIT is RECORDED — the ratio has a numerator, not just a denominator" {
  command -v jq >/dev/null 2>&1 || skip "emit_fire_event writes rows only when jq is present"
  LOG="$HOME/.claude/logs/handoffs.jsonl"
  fire 10 1.00                       # idle box, headroom pinned to 64 by setup() ⇒ both terms admit
  [ "$status" -ne 9 ]
  run bash -c "jq -rc 'select(.class==\"admitted\")|[.gate,.verdict,.basis]|@tsv' '$LOG'"
  [ "$output" = "$(printf 'capacity\tadmit\tmeasured')" ]
  # the numbers travel with the verdict — an admit with no numbers is worse than a refusal with
  # none, because nothing about it looks wrong
  run bash -c "jq -r 'select(.class==\"admitted\")|.detail' '$LOG'"
  [ "$output" = "load 1.00 on 10 cores = 0.10/core (ceiling 2.0/core) · reclaimable 64GB (floor 4GB)" ]
}

@test "26 an admit carries NO engaged field — absent, never a fabricated false (R9)" {
  # An admit's fire has not happened yet, so `engaged:false` would be an invented outcome AND would
  # land in group_by(.engaged) — the engagement-rate metric (V2 M-1) — deflating it by one row per
  # admitted fire. A refusal is terminal, so IT keeps engaged:false; the asymmetry is the point.
  command -v jq >/dev/null 2>&1 || skip "emit_fire_event writes rows only when jq is present"
  LOG="$HOME/.claude/logs/handoffs.jsonl"
  fire 10 1.00
  fire 10 27.16
  run bash -c "jq -rs '[.[]|select(.verdict==\"admit\" and has(\"engaged\"))]|length' '$LOG'"
  [ "$output" = "0" ]
  # positive control: the refusal in the same log DOES carry it, so "0" above is a property of the
  # admit row and not of a jq expression that cannot match anything
  run bash -c "jq -rs '[.[]|select(.verdict==\"refuse\" and .engaged==false)]|length' '$LOG'"
  [ "$output" = "1" ]
}

@test "27 FAIL-OPEN admits are filed as fail-open — a dead probe cannot read back as a healthy box" {
  # The load-bearing one. The gate fails OPEN on an unreadable instrument, so a broken sysctl yields
  # a 100%-admit population indistinguishable from a quiet fleet: the gate DELETED, reading as the
  # gate HEALTHY. basis splits measured from not-measured.
  command -v jq >/dev/null 2>&1 || skip "emit_fire_event writes rows only when jq is present"
  LOG="$HOME/.claude/logs/handoffs.jsonl"
  fire abc 1.00                                   # hw.ncpu unreadable ⇒ load term never evaluated
  [ "$status" -ne 9 ]
  run bash -c "jq -r 'select(.class==\"admitted\")|.basis' '$LOG'"
  [ "$output" = "fail-open" ]
  run bash -c "jq -r 'select(.class==\"admitted\")|.detail' '$LOG'"
  echo "$output" | grep -q "hw.ncpu unreadable" || false
  echo "$output" | grep -q "load term not evaluated" || false
  # and an unreadable vm_stat is the headroom term's equivalent — the SECOND term must not be the
  # silent one, exactly as test 21 established for the refusal side
  printf '#!/bin/bash\necho garbage\n' > "$BIN/vm_stat"; chmod +x "$BIN/vm_stat"
  run env STUB_NCPU=10 STUB_LOAD=1.00 CC_FIRE_HEADROOM_OVERRIDE= \
      bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -ne 9 ]
  run bash -c "jq -rs '[.[]|select(.basis==\"fail-open\")]|length' '$LOG'"
  [ "$output" = "2" ]
}

@test "28 the two DISABLED bases are recorded, not silent — gate-off and load-only" {
  # A kill switch that leaves no trace lets an override-heavy window be counted later as evidence
  # the gate was exercised. Neither is `measured`, and that is the whole distinction.
  command -v jq >/dev/null 2>&1 || skip "emit_fire_event writes rows only when jq is present"
  LOG="$HOME/.claude/logs/handoffs.jsonl"
  run env STUB_NCPU=10 STUB_LOAD=1.00 CC_FIRE_CAPACITY_GATE=off \
      bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -ne 9 ]
  run env STUB_NCPU=10 STUB_LOAD=1.00 CC_FIRE_HEADROOM_GATE=off \
      bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -ne 9 ]
  run bash -c "jq -rs '[.[]|select(.class==\"admitted\")|.basis]|sort|join(\",\")' '$LOG'"
  [ "$output" = "gate-off,load-only" ]
  # the load-only row still carries the term it DID measure — one disabled term must not blind the
  # record to the other
  run bash -c "jq -r 'select(.basis==\"load-only\")|.detail' '$LOG'"
  echo "$output" | grep -q "0.10/core" || false
  echo "$output" | grep -q "headroom term off" || false
}

@test "29 THE RATIO IS READABLE — one symmetric predicate returns both verdicts" {
  # The item this whole block exists for. Two hand-written asymmetric predicates (class=="admitted"
  # vs class=="refused") are what produce mis-derivations: `refused` spans the PAYLOAD gates too, so
  # that denominator is polluted. `gate` carries on both sides, so the ratio is one select().
  command -v jq >/dev/null 2>&1 || skip "emit_fire_event writes rows only when jq is present"
  LOG="$HOME/.claude/logs/handoffs.jsonl"
  fire 10 1.00                                                            # admit (measured)
  fire 10 27.16                                                           # refuse (load term)
  fire_h 1.50                                                             # refuse (headroom term)
  run bash -c "jq -rs '[.[]|select(.gate==\"capacity\")]|group_by(.verdict)|map(\"\(.[0].verdict)=\(length)\")|join(\" \")' '$LOG'"
  [ "$output" = "admit=1 refuse=2" ]
}

@test "30 a PAYLOAD refusal is NOT in the capacity denominator — gate names its own surface" {
  # If payload refusals counted as capacity refusals the ratio would understate the admit side, and
  # that is precisely the class of error being fixed. A payload gate carries gate:"payload".
  #
  # Both cases here were found BY this test and are new records (2026-07-31): the empty-payload
  # (FM-D) and /goal-line-over-cap guards were the last two pre-fire refusals that wrote NOTHING
  # anywhere — F13's own defect, two guards upstream of the one it fixed. They run BEFORE
  # capacity_gate, so a correct log carries the payload refusal and no capacity row at all.
  command -v jq >/dev/null 2>&1 || skip "emit_fire_event writes rows only when jq is present"
  LOG="$HOME/.claude/logs/handoffs.jsonl"
  printf '/goal %s\n' "$(head -c 5000 < /dev/zero | tr '\0' 'x')" > "$BATS_TEST_TMPDIR/over.txt"
  run env STUB_NCPU=10 STUB_LOAD=1.00 bash "$HF" --prompt-file "$BATS_TEST_TMPDIR/over.txt" --dry-run
  [ "$status" -ne 0 ]
  : > "$BATS_TEST_TMPDIR/empty.txt"
  run env STUB_NCPU=10 STUB_LOAD=1.00 bash "$HF" --prompt-file "$BATS_TEST_TMPDIR/empty.txt" --dry-run
  [ "$status" -ne 0 ]
  run bash -c "jq -rs '[.[]|select(.class==\"refused\")|\"\(.gate):\(.refuse_reason)\"]|sort|join(\" \")' '$LOG'"
  [ "$output" = "payload:payload-empty payload:payload-goal-line" ]
  run bash -c "jq -rs '[.[]|select(.gate==\"capacity\")]|length' '$LOG'"
  [ "$output" = "0" ]
}

@test "31 ADMIT-COVERAGE + ENUM guard — no silent admit branch, no unmapped refusal reason" {
  # Two standing properties, not one-time edits. (a) every `return 0` in capacity_gate() is preceded
  # by an emit_gate_admit, so a term added later with a bare `return 0` cannot re-open the hole this
  # block closed; (b) every refusal reason the script actually emits maps to a named gate in
  # _fire_gate_of, so a new reason cannot fall into the fail-visible `*)` arm and quietly go missing
  # from the capacity denominator.
  local body prev line n=0
  body="$(awk '/^capacity_gate\(\) \{/{p=1} p{print} p&&/^\}$/{exit}' "$REPO/scripts/handoff-fire.sh")"
  [ -n "$body" ] || { echo "capacity_gate() not found — the extractor, not the gate, is broken"; false; }
  # Normalise before scanning, or the lint fails on a correct tree twice over: comments are stripped
  # because this function's own prose says `return 0` (a scan that reads its own documentation as
  # code), and line-continuations are JOINED because an emit split across `\` puts the call two
  # physical lines above its return — an adjacency test on raw lines would call that unrecorded.
  body="$(printf '%s\n' "$body" | sed 's/^[[:space:]]*//' | grep -v '^#' \
            | sed -e :a -e '/\\$/N; s/\\\n//; ta')"
  prev=""
  while IFS= read -r line; do
    case "$line" in
      *"return 0"*)
        n=$((n + 1))
        printf '%s\n%s\n' "$prev" "$line" | grep -q 'emit_gate_admit' \
          || { echo "UNRECORDED ADMIT — a 'return 0' with no emit_gate_admit: $line"; false; } ;;
    esac
    prev="$line"
  done <<< "$body"
  [ "$n" -ge 9 ] || { echo "expected >=9 admitting returns, found $n — extractor drifted"; false; }
  # positive control: the same scan MUST reject a body whose return is unrecorded, or (a) is vacuous
  prev=""; rc=0
  while IFS= read -r line; do
    case "$line" in
      *"return 0"*) printf '%s\n%s\n' "$prev" "$line" | grep -q 'emit_gate_admit' || rc=1 ;;
    esac
    prev="$line"
  done <<< "$(printf 'capacity_gate() {\n  return 0\n}\n')"
  [ "$rc" -eq 1 ] || { echo "the admit-coverage scan cannot fail — it is a deleted check"; false; }
  # (b) ENUM: every reason passed to emit_fire_refusal is mapped
  local reason mapped
  mapped="$(awk '/^_fire_gate_of\(\)/{p=1} p{print} p&&/^\}$/{exit}' "$REPO/scripts/handoff-fire.sh")"
  [ -n "$mapped" ] || { echo "_fire_gate_of() not found"; false; }
  while read -r reason; do
    [ -n "$reason" ] || continue
    case "$reason" in
      capacity|headroom) printf '%s' "$mapped" | grep -q 'capacity|headroom' || false ;;
      payload-*)         printf '%s' "$mapped" | grep -q 'payload-\*'        || false ;;
      *) echo "UNMAPPED refusal reason '$reason' — it will fall into the fail-visible *) arm and be"
         echo "missing from every gate denominator. Add it to _fire_gate_of and to this case."; false ;;
    esac
  done <<< "$(grep -oE 'emit_fire_refusal [a-z-]+' "$REPO/scripts/handoff-fire.sh" | awk '{print $2}' | sort -u)"
}
