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
}

# fire() runs the real script with the stub sysctl in front; all cases are --dry-run.
fire() { run env STUB_NCPU="$1" STUB_LOAD="$2" bash "$HF" --prompt-file "$PAYLOAD" --dry-run "${@:3}"; }

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
