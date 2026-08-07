#!/usr/bin/env bats
# scripts/lib/capacity-admit.sh — the BOUNDED capacity term for the spawn paths that
# handoff-fire.sh's capacity_gate() does not reach (MACHINE_CAPACITY_V2 §12.1's bypass table:
# boot-resume.sh, limit-recover/lr-fire-resume.sh, ~/.reso/bin/reso-resume-one, the Agent tool).
#
# WHY THE BOUND IS THE CENTRAL PROPERTY UNDER TEST, not the ceiling. §12.2 refuted the obvious fix
# (bind capacity_gate() everywhere) with a live measurement: 2026-07-31 12:13, load 21.55 on 10
# cores = 2.16/core — over the 2.0 ceiling — on a box with 13 sessions, 24 GB free and 0 B
# compressor, i.e. perfectly healthy. The existing gate bound to all seven paths refuses EVERY
# spawn at that moment, including every recovery path, and cannot recover: iTerm2 + WindowServer +
# XProtect are ~2.4 UNSHEDDABLE cores, so refusing spawns does not lower the number it reads.
# The 2026-08-07 deploy-lane exchange narrowed that into a law (inertness-generator §9, accepted):
# "No gate on an actuation path may be unbounded. Every affirmative-permission predicate must carry
# a finite budget whose expiry converts the standing state into an EVENT."
# Case 4 is that law. If it ever goes RED this library has become the outage §12.2 measured.
#
# sysctl and vm_stat are replaced by the CC_ADMIT_LOADAVG_OVERRIDE / CC_ADMIT_HEADROOM_OVERRIDE
# seams, so load and headroom are INPUTS, not ambient facts — otherwise every assertion here would
# flip with the mood of the machine running the suite. The P-series below pins the real instruments
# separately, so the overrides cannot hide a probe that stopped working.
#
# RED-PROOF (recorded 2026-08-07): every REFUSE case was re-run with CC_ADMIT_GATE=off and returned
# 0 instead of 9, and case 4's bound was re-run with a mutated CC_ADMIT_BUDGET to confirm the admit
# lands on budget+1 and not at a fixed index. A control that cannot fail proves nothing.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/capacity-admit.sh"
  # HERMETICITY: the library writes budget state and an IDL row. Fixture both under the test tmpdir
  # so a case can never read or mutate the operator's live ~/.claude/autonomy.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # A page must never reach the operator from a test run. Point the notifier at a recorder.
  export CC_ADMIT_NOTIFY_BIN="$BATS_TEST_TMPDIR/notify"
  cat > "$CC_ADMIT_NOTIFY_BIN" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/pages.txt"
EOF
  chmod +x "$CC_ADMIT_NOTIFY_BIN"
  # Deterministic box unless a case says otherwise: 10 cores, quiet, plenty of headroom.
  export CC_ADMIT_LOADAVG_OVERRIDE=1.0
  export CC_ADMIT_HEADROOM_OVERRIDE=64
}

# Run one evaluation in a fresh subshell so a case cannot inherit another's shell state.
# The gate's rc is the SUBSHELL's rc — deliberately the last statement. An earlier version ended
# with `cc_capacity_admit_reason`, whose own 0 masked every REFUSE, and cases 02/03 passed a rc-9
# assertion against rc 0 until they were run. A helper that cannot report a refusal makes every
# refusal case vacuous.
admit() { # $1=caller  $2=what   → prints the reason, exits with the gate's rc
  bash -c '. "$1"; cc_capacity_admit "$2" "$3"; rc=$?; cc_capacity_admit_reason; exit $rc' \
    _ "$LIB" "$1" "${2:-spawn}"
}

idl_field() { # $1=jq path → newline-separated values, in order
  jq -r "$1" "$CC_ADMIT_IDL"
}

@test "01 healthy box ADMITS, and records basis=measured with BOTH terms' numbers" {
  run admit c1 "a spawn"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ADMIT"* ]] || false
  # §9.5.1: an admit with no numbers is worse than a refusal with none, because nothing about it
  # looks wrong. Both terms must be in the row.
  [ "$(idl_field '.basis')" = "measured" ]
  [ "$(idl_field '.verdict')" = "admit" ]
  [[ "$(idl_field '.detail')" == *"/core"* ]] || false
  [[ "$(idl_field '.detail')" == *"reclaimable"* ]]
}

@test "02 load over the ceiling REFUSES with rc 9, term=load" {
  export CC_ADMIT_LOADAVG_OVERRIDE=99
  run admit c2 "a spawn"
  [ "$status" -eq 9 ]
  [ "$(idl_field '.verdict')" = "refuse" ]
  [ "$(idl_field '.term')" = "load" ]
  # basis stays `measured` on a refusal: both instruments read fine, it is the BOX that is over.
  # Folding the term into basis would corrupt the one vocabulary §9.5.1 says to split on.
  [ "$(idl_field '.basis')" = "measured" ]
}

@test "03 headroom under the floor REFUSES with rc 9, term=headroom (load term clear)" {
  export CC_ADMIT_HEADROOM_OVERRIDE=0.5
  run admit c3 "a spawn"
  [ "$status" -eq 9 ]
  [ "$(idl_field '.term')" = "headroom" ]
  [[ "$(idl_field '.detail')" == *"floor 4GB"* ]]
}

@test "04 THE BOUND (§9's law) — N refusals then ADMIT+page, and the counter resets" {
  # The single property that separates this library from the architecture §12.2 refuted. A gate on
  # an actuation path that can refuse forever IS the outage; this asserts it structurally cannot.
  local rcs=""
  for i in 1 2 3 4; do
    run bash -c '. "$1"; CC_ADMIT_BUDGET=3 CC_ADMIT_LOADAVG_OVERRIDE=99 cc_capacity_admit c4 "s$2"' _ "$LIB" "$i"
    rcs="$rcs$status,"
  done
  # three refusals, then the budget expires and the gate ADMITS rather than standing
  [ "$rcs" = "9,9,9,0," ]
  [ "$(idl_field 'select(.basis=="budget-expired") | .verdict')" = "admit" ]
  # the expiry is an EVENT, not a silent release — it must page
  [ -f "$BATS_TEST_TMPDIR/pages.txt" ]
  grep -q "spent its 3-refusal budget" "$BATS_TEST_TMPDIR/pages.txt"
  # and the counter resets, so the bound is on CONSECUTIVE refusals, not lifetime ones
  run bash -c '. "$1"; CC_ADMIT_BUDGET=3 CC_ADMIT_LOADAVG_OVERRIDE=99 cc_capacity_admit c4 "s5"' _ "$LIB"
  [ "$status" -eq 9 ]
}

@test "04b the bound tracks CC_ADMIT_BUDGET — the admit is not at a fixed index" {
  # Control for case 4: if the admit landed on call 4 regardless of budget, case 4 would pass
  # vacuously against a hardcoded counter rather than a real bound.
  local rcs=""
  for i in 1 2; do
    run bash -c '. "$1"; CC_ADMIT_BUDGET=1 CC_ADMIT_LOADAVG_OVERRIDE=99 cc_capacity_admit c4b "s$2"' _ "$LIB" "$i"
    rcs="$rcs$status,"
  done
  [ "$rcs" = "9,0," ]
}

@test "04c budget=0 never refuses — a pure advisory tier, still fully recorded" {
  run bash -c '. "$1"; CC_ADMIT_BUDGET=0 CC_ADMIT_LOADAVG_OVERRIDE=99 cc_capacity_admit c4c "s"' _ "$LIB"
  [ "$status" -eq 0 ]
  [ "$(idl_field '.basis')" = "budget-expired" ]
}

@test "05 an ADMIT resets a partially-spent budget" {
  run bash -c '. "$1"; CC_ADMIT_BUDGET=3 CC_ADMIT_LOADAVG_OVERRIDE=99 cc_capacity_admit c5 "s"' _ "$LIB"
  [ "$status" -eq 9 ]
  [ "$(cat "$CC_ADMIT_STATE_DIR/c5.refusals")" = "1" ]
  run bash -c '. "$1"; cc_capacity_admit c5 "s"' _ "$LIB"     # healthy box → admit
  [ "$status" -eq 0 ]
  [ -z "$(cat "$CC_ADMIT_STATE_DIR/c5.refusals")" ]
}

@test "06 a dead probe FAILS OPEN and is recorded as fail-open, naming the resolved binary" {
  # §9.5.1: the gate fails open on an unreadable sysctl, so a dead probe otherwise manufactures a
  # 100%-admit population indistinguishable from a quiet box — the gate deleted, reading as healthy.
  # The row must name the RESOLVED BINARY, not just the failing key: handoff-fire's 222 dead rows
  # all carried one identical string, so the ledger could not tell a PATH miss from a new cause.
  run bash -c '. "$1"; unset CC_ADMIT_LOADAVG_OVERRIDE
               CC_ADMIT_SYSCTL=/nonexistent/sysctl cc_capacity_admit c6 "s"' _ "$LIB"
  [ "$status" -eq 0 ]
  [ "$(idl_field '.basis')" = "fail-open" ]
  [[ "$(idl_field '.detail')" == *"/nonexistent/sysctl"* ]]
}

@test "07 CC_ADMIT_GATE=off ADMITS but is RECORDED — never a silent admit" {
  # The row that keeps "the gate was OFF" out of the measured population.
  run bash -c '. "$1"; CC_ADMIT_GATE=off CC_ADMIT_LOADAVG_OVERRIDE=99 cc_capacity_admit c7 "s"' _ "$LIB"
  [ "$status" -eq 0 ]
  [ "$(idl_field '.basis')" = "gate-off" ]
}

@test "08 an unusable caller id FAILS OPEN — an untracked bound is an UNBOUNDED gate" {
  # Refusing here would convict on our own bad wiring, and worse: with no state file the refusal
  # could never expire, re-creating the exact unbounded gate §12.2 refuted.
  run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 cc_capacity_admit "bad/id" "s"' _ "$LIB"
  [ "$status" -eq 0 ]
  [ "$(idl_field '.basis')" = "fail-open" ]
  [[ "$(idl_field '.detail')" == *"bound untrackable"* ]]
}

@test "09 CC_ADMIT_LOAD_TERM=off runs headroom only, and says so in basis" {
  # The Agent-tool policy. A single-term window must never be counted as evidence that both terms
  # were exercised, so it gets its own basis rather than `measured`.
  run bash -c '. "$1"; CC_ADMIT_LOAD_TERM=off CC_ADMIT_LOADAVG_OVERRIDE=99 cc_capacity_admit c9 "s"' _ "$LIB"
  [ "$status" -eq 0 ]                                   # load is 99/core and is IGNORED
  [ "$(idl_field '.basis')" = "headroom-only" ]
}

@test "09b CC_ADMIT_LOAD_TERM=off still enforces the headroom term" {
  # Guards against the switch disabling the whole gate rather than one term.
  run bash -c '. "$1"; CC_ADMIT_LOAD_TERM=off CC_ADMIT_HEADROOM_OVERRIDE=0.5 cc_capacity_admit c9b "s"' _ "$LIB"
  [ "$status" -eq 9 ]
  [ "$(idl_field '.term')" = "headroom" ]
}

@test "10 BOTH terms off records gate-off, never load-only — a blind eval is not a real one" {
  run bash -c '. "$1"; CC_ADMIT_LOAD_TERM=off CC_ADMIT_HEADROOM_TERM=off cc_capacity_admit c10 "s"' _ "$LIB"
  [ "$status" -eq 0 ]
  [ "$(idl_field '.basis')" = "gate-off" ]
}

@test "11 ADMIT-COVERAGE — no 'return 0' in cc_capacity_admit without a preceding record" {
  # A STANDING property, not a one-time edit: the same guard capacity_gate() carries. A term added
  # later with a bare `return 0` re-opens the silent-admit hole and must go RED here.
  body="$(awk '/^cc_capacity_admit\(\) \{/{p=1} p{print} p&&/^\}$/{exit}' "$LIB")"
  [ -n "$body" ] || { echo "cc_capacity_admit() not found — the extractor, not the gate, is broken"; false; }
  # A 4-line trailing window, not 2. An emit is routinely a wrapped call — `_cc_admit_emit … \` plus
  # its continuation, then `_cc_admit_reset; return 0` — and a 2-line window sees only the
  # continuation and convicts a correctly-recorded branch. That is a false RED, and a check that
  # cries wolf on a healthy subject gets disabled, taking the real property with it.
  scan() { # stdin = a function body → rc 1 if any `return 0` has no emit within 4 lines above
    local line rc=0 w1="" w2="" w3="" w4=""
    while IFS= read -r line; do
      case "$line" in
        *"return 0"*)
          printf '%s\n%s\n%s\n%s\n%s\n' "$w1" "$w2" "$w3" "$w4" "$line" \
            | grep -qE '_cc_admit_emit|_cc_admit_spend' \
            || { echo "UNRECORDED ADMIT — a 'return 0' with no emit within 4 lines: $line"; rc=1; } ;;
      esac
      w1="$w2"; w2="$w3"; w3="$w4"; w4="$line"
    done
    return $rc
  }
  scan <<< "$body"
  # MUTATION CONTROL — the check must be able to FAIL, or this case passes vacuously. The mutant is
  # a bare `return 0` with four blank lines above it: within the window, and still unrecorded.
  if scan <<< "$(printf 'cc_capacity_admit() {\n\n\n\n\n  return 0\n}\n')" >/dev/null 2>&1; then
    echo "the coverage check cannot detect a bare return 0 — it proves nothing"; false
  fi
}

@test "12 the library never defines log_idl — it must not clobber a caller's own writer" {
  # boot-resume.sh defines its OWN log_idl emitting tool:"boot-resume" rows. If this library sourced
  # hooks/lib/idl-log.sh (which defines a global log_idl) it would silently overwrite the caller's
  # telemetry to install a gate — a worse defect than the ungated spawn it exists to fix.
  run bash -c 'log_idl() { echo "CALLER-OWN"; }; . "$1"; log_idl x' _ "$LIB"
  [ "$output" = "CALLER-OWN" ]
  # …and no SOURCE line for it. Keyed on the source statement, not the string: the header explains
  # at length WHY it must not source that lib, and a bare `grep idl-log.sh` convicts the explanation.
  ! grep -qE '^[^#]*(\.|source)[[:space:]]+[^#]*idl-log\.sh' "$LIB"
}

@test "13 every IDL row carries gate=capacity-admit on BOTH verdicts (one predicate, §9.5.1)" {
  bash -c '. "$1"; cc_capacity_admit c13 "s"' _ "$LIB" >/dev/null || true
  # `|| true`: the refusal's rc 9 is the POINT of this case, and under bats' errexit an unguarded
  # non-zero aborts the test before a single assertion runs.
  bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 cc_capacity_admit c13 "s"' _ "$LIB" >/dev/null || true
  [ "$(jq -rs 'map(select(.gate=="capacity-admit")) | length' "$CC_ADMIT_IDL")" = "2" ]
  [ "$(jq -rs 'map(.verdict) | sort | join(",")' "$CC_ADMIT_IDL")" = "admit,refuse" ]
}

@test "14 rows stay slurpable when `what` carries quotes/newlines (the malformed-line class)" {
  # ONE malformed line aborts the cc-audit `jq -rs` slurp, which then reads as "no records" and
  # silently flips the abstain alarm GREEN. Every field is jq-encoded for exactly this.
  bash -c '. "$1"; cc_capacity_admit c14 "$(printf '"'"'a"b\nc\\d'"'"')"' _ "$LIB" >/dev/null
  run jq -rs 'length' "$CC_ADMIT_IDL"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "P1 the REAL sysctl is reachable at the absolute path the library resolves" {
  # The overrides above make every case above blind to a probe that stopped working. 81871d23:
  # launchd's PATH lacks /usr/sbin, and three capacity-alarm rungs failed open on exactly that.
  [ -x /usr/sbin/sysctl ]
  run /usr/sbin/sysctl -n hw.ncpu
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "P2 vm_stat is reachable on a MINIMAL PATH (why it stays on its bare name)" {
  # The library resolves sysctl absolutely but leaves vm_stat bare, on the claim that /usr/bin is
  # the floor of every PATH including a launchd one. That is a claim about the box; check it.
  run env PATH=/usr/bin:/bin bash -c 'command -v vm_stat'
  [ "$status" -eq 0 ]
}

@test "P3 a live end-to-end evaluation with NO overrides reads both real instruments" {
  # Neither override set: proves the two probes actually parse on this box and produce a verdict,
  # which every case above assumes and none of them exercises.
  run bash -c 'unset CC_ADMIT_LOADAVG_OVERRIDE CC_ADMIT_HEADROOM_OVERRIDE
               . "$1"; cc_capacity_admit p3 "s"; echo "rc=$?"' _ "$LIB"
  # Either verdict is legitimate — the box's real state decides. What must NOT happen is a
  # fail-open, which would mean a probe is dead on the machine running this suite.
  [ "$(idl_field '.basis')" != "fail-open" ]
  [[ "$(idl_field '.detail')" == *"/core"* ]]
}
