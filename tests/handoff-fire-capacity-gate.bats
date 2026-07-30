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

@test "23 PIN-GUARD (M11) — the three red-by-load fire suites pin BOTH terms off in setup()" {
  # 16 corpus tests were RED on a PRISTINE tree purely because the box was busy (map R-1) — a gate
  # failing its own suite and blocking deploy verification. The remedy is a STANDING property of the
  # corpus, not a one-time edit, so it gets a guard: a new fire suite, or a setup() rewrite that
  # drops the pin, goes RED here instead of quietly making the machine's mood a test input.
  local f rc
  for f in handoff-fire-focus.bats handoff-fire-payload-lint.bats fire-engagement.bats; do
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
