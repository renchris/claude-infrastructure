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
# sysctl is STUBBED VIA CC_FIRE_SYSCTL so load/core count are inputs, not ambient facts — otherwise
# every assertion below would flip with the mood of the machine running the suite. Each case runs
# --dry-run so an ADMIT verdict never actually fires a session. (It was stubbed on PATH until item
# 02ae8ae886a1; the gate now resolves sysctl absolutely, so a PATH-only stub would be stepped over
# and these cases would quietly start reading the real box. See setup() and the P-series below.)
#
# RED-PROOF (recorded 2026-07-29): case 1 was replayed against the pristine pre-change
# scripts/handoff-fire.sh recovered via `git archive origin/main` (2595 lines, 0 occurrences of
# capacity_gate) and exited 0, not 9 — so the exit-9 assertions below are caused BY the gate and
# not by some pre-existing refusal path.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  # The hardware TERMS (resolver, both probes, both verdict awks, both default numbers) live here
  # since 2026-08-07 and are shared with cc_capacity_admit(); the POLICY — unbounded, --recycle
  # exempt, CC_FIRE_* namespace, handoffs.jsonl records — stays in capacity_gate(). Every case in
  # this file still tests capacity_gate through the real script; the P-series below composes the two.
  LIB="$REPO/scripts/lib/capacity-admit.sh"
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
  # The stub is reached through the SEAM, not through PATH order (item 02ae8ae886a1). The gate now
  # resolves /usr/sbin/sysctl absolutely, so a PATH-only stub would be stepped over and every case
  # below would silently start reading the REAL box — the exact shape of a control that decays into
  # a no-op while staying green (memory control-calibrated-to-implementation-decays). Pointing
  # CC_FIRE_SYSCTL at the same file keeps the stub authoritative and makes the suite independent of
  # PATH ordering. `export PATH` above stays for vm_stat, which is stubbed on PATH by vmstub().
  export CC_FIRE_SYSCTL="$BIN/sysctl"
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
  #
  # `^[^#]*` — the CALL, not a comment that quotes it. This case went RED on a correct tree the
  # moment capacity_gate's header explained what its call site does, because the unanchored grep
  # returned two line numbers and `[ "2643\n3912" -gt … ]` is not an integer expression. Same shape
  # as case 20's citation-vs-claim split in capacity-admit-coverage.bats: position is the
  # discriminator, and a guard a future comment can convict is a guard that will be edited away
  # (memory `guard-proxy-fails-in-both-directions`).
  run bash -c "grep -nE '^[^#]*capacity_gate \|\| exit 9' '$HF' | cut -d: -f1"
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
  # The detail gained the PRESENCE reading on 2026-08-12 (§W3 item 1, backlog 8ae4b508f274): this gate
  # now consults the session presence beat and records what it said AT THE MOMENT IT DECIDED, because
  # "with the operator active, unattended spawns yield" is only checkable afterwards if both sides of
  # the decision wrote their reading down. `unknown` is the correct value under a fixtured HOME — this
  # suite has no beat dir — so it is deterministic here rather than a machine-mood read.
  [ "$output" = "reclaimable 1.50GB < floor 4GB · operator unknown" ]
}

@test "22 --recycle is EXEMPT from BOTH terms — a replacement fire is net-zero panes AND net-zero memory" {
  # Gating a recycle would strand the very handoff that SHEDS the memory (fail-closed-as-amplifier);
  # the headroom term inherits that exemption from the call site, so it is asserted, not assumed.
  run env STUB_NCPU=10 STUB_LOAD=27.16 CC_FIRE_HEADROOM_OVERRIDE=0.10 \
      bash "$HF" --prompt-file "$PAYLOAD" --dry-run --recycle
  [ "$status" -ne 9 ]
}

# _setup_gate_off <file> — 0 when that file's setup() DISABLES both gate terms (pin form 1).
# Split out from _setup_pins so the two questions stay separable: "is this suite load-insensitive"
# (either form) and "does this suite turn the gate OFF" (this one). Test 23's DISJOINTNESS clause
# needs the second and would be silently satisfied by the first — the shape of an assertion whose
# span outgrew its subject.
_setup_gate_off() {
  local blk
  blk="$(awk '/setup\(\)[[:space:]]*\{/{p=1} p{print} p&&/^\}/{exit}' "$1")"
  printf '%s\n' "$blk" | grep -q 'export CC_FIRE_CAPACITY_GATE=off' || return 1
  printf '%s\n' "$blk" | grep -q 'export CC_FIRE_HEADROOM_GATE=off'  || return 1
  return 0
}

# _setup_pins <file> — 0 when that file's setup() block makes the gate load-INSENSITIVE, by either
# of the two sufficient forms below.
_setup_pins() {
  local blk
  blk="$(awk '/setup\(\)[[:space:]]*\{/{p=1} p{print} p&&/^\}/{exit}' "$1")"
  # FORM 1 — turn BOTH gate terms OFF. What a suite that merely happens to fire should do.
  if _setup_gate_off "$1"; then return 0; fi
  # FORM 2 — make the gate's INPUTS synthetic. Added 2026-08-08, when tests/handoff-fire-cloud.bats
  # (G5, the off-box venue branch) became the SECOND suite whose SUBJECT is this gate. Form 1 is
  # unavailable to such a suite by construction: turning the gate off deletes the only thing it
  # tests. That is precisely why case 25 has always exempted THIS file by name — and a name is not
  # a property, so the exemption stopped covering the population the moment a second gate suite
  # existed.
  #
  # This is the second SUFFICIENT condition for the property the pin actually protects — ambient
  # box load cannot flip the suite — not a widening of it. A setup() exporting CC_FIRE_SYSCTL (load
  # and core count become stub output) AND CC_FIRE_HEADROOM_OVERRIDE (the memory term becomes a
  # literal) has closed BOTH paths by which the real machine reaches the gate, which is exactly
  # what form 1 achieves, and it is checkable the same way. A suite with NEITHER form still goes
  # RED, so the ratchet keeps its teeth — this adds a second door, not a hole.
  if printf '%s\n' "$blk" | grep -q 'export CC_FIRE_SYSCTL=' \
  && printf '%s\n' "$blk" | grep -q 'export CC_FIRE_HEADROOM_OVERRIDE='; then return 0; fi
  return 1
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
  #
  # Asserted against _setup_gate_off, not _setup_pins, since 2026-08-08. The clause has always
  # meant "this suite does not DISABLE the gate"; it was written as `! _setup_pins` only because
  # the two were the same predicate. They stopped being the same when _setup_pins grew form 2
  # (synthetic inputs), which is how THIS suite is load-insensitive — so the old wording would now
  # convict the file for the very technique that keeps its coverage alive.
  rc=0; _setup_gate_off "$BATS_TEST_FILENAME" || rc=$?
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
  # + the presence reading (§W3 item 1) — see case 21 for why it rides on the ADMIT row too.
  [ "$output" = "load 1.00 on 10 cores = 0.10/core (ceiling 2.0/core) · reclaimable 64GB (floor 4GB) · operator unknown" ]
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
        # `_cc_fire_bound` counts as a recorder, and that is a DEEPENING of this invariant rather
        # than a hole in it: as of 2026-08-12 (§W3 item 2) a refusal here is BOUNDED, and the release
        # branch — the one that turns a standing refusal into an admit — lives in that helper, which
        # emits on every one of its own admitting paths. The property is "no silent admit", never
        # "the literal emit is on the previous line"; the nested scan below enforces it there, so the
        # guard follows the emit down instead of being satisfied by its absence.
        printf '%s\n%s\n' "$prev" "$line" | grep -qE 'emit_gate_admit|_cc_fire_bound' \
          || { echo "UNRECORDED ADMIT — a 'return 0' with no emit_gate_admit: $line"; false; } ;;
    esac
    prev="$line"
  done <<< "$body"
  [ "$n" -ge 9 ] || { echo "expected >=9 admitting returns, found $n — extractor drifted"; false; }
  # (a2) THE SAME SCAN, ONE LEVEL DOWN — every `return 0` in _cc_fire_bound() is an ADMIT into a
  # saturated box (the bound released, or it could not be tracked), so each must carry its own
  # emit_gate_admit. Without this, accepting `_cc_fire_bound` as a recorder above would move the hole
  # rather than close it.
  local bbody bn=0
  bbody="$(awk '/^_cc_fire_bound\(\) \{/{p=1} p{print} p&&/^\}$/{exit}' "$REPO/scripts/handoff-fire.sh")"
  [ -n "$bbody" ] || { echo "_cc_fire_bound() not found — the bound the operator's path depends on is missing"; false; }
  bbody="$(printf '%s\n' "$bbody" | sed 's/^[[:space:]]*//' | grep -v '^#' \
             | sed -e :a -e '/\\$/N; s/\\\n//; ta')"
  prev=""
  while IFS= read -r line; do
    case "$line" in
      *"return 0"*)
        bn=$((bn + 1))
        printf '%s\n%s\n' "$prev" "$line" | grep -q 'emit_gate_admit' \
          || { echo "UNRECORDED RELEASE — a 'return 0' in _cc_fire_bound with no emit_gate_admit: $line"; false; } ;;
    esac
    prev="$line"
  done <<< "$bbody"
  [ "$bn" -ge 3 ] || { echo "expected >=3 releasing returns in _cc_fire_bound, found $bn"; false; }
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
      # G5 — the off-box venue's refusals (cloud-optin, cloud-router-absent,
      # cloud-account-headroom, cloud-account-policy) map to their OWN gate name, deliberately not
      # capacity's: a cloud fire never measured this box, so counting its refusals into the
      # capacity denominator would mix two populations read by two different instruments.
      cloud-*)           printf '%s' "$mapped" | grep -q 'cloud-\*'          || false ;;
      payload-*)         printf '%s' "$mapped" | grep -q 'payload-\*'        || false ;;
      # ARGV surface (an unescaped `!` in --extra). THIS ARM IS THE GUARD'S FIRST CATCH: `extra-bang`
      # shipped unmapped and this case was RED on trunk over it, which also meant it could not report
      # any OTHER unmapped reason — a guard blocked by its own first finding sees nothing after it.
      extra-*)           printf '%s' "$mapped" | grep -q 'extra-\*'          || false ;;
      # L1-b — the in-flight-subagent refusal (a --recycle or self-close that would SIGKILL this
      # session's own Agent-tool subagents). Its own gate name for the same reason cloud-* has one:
      # it measured the predecessor's live work, not the box, the payload or the argv.
      live-subagents)    printf '%s' "$mapped" | grep -q 'live-subagents'    || false ;;
      *) echo "UNMAPPED refusal reason '$reason' — it will fall into the fail-visible *) arm and be"
         echo "missing from every gate denominator. Add it to _fire_gate_of and to this case."; false ;;
    esac
  done <<< "$(grep -oE 'emit_fire_refusal [a-z-]+' "$REPO/scripts/handoff-fire.sh" | awk '{print $2}' | sort -u)"
}

# ---- THE EXTRACTION'S OWN FAILURE MODE (item a27a4d9485da, 2026-08-07) ------------------------
# The hardware terms moved to scripts/lib/capacity-admit.sh, so for the first time this gate has a
# DEPENDENCY IT CAN LOSE — and its call site turns any non-zero status into rc 9. An undefined
# cc_hw_* would therefore make ONE missing file refuse EVERY fire on the box: fail-CLOSED, the
# §12.2 amplifier the bounded sibling exists to avoid, arriving through the back door of a refactor.
# Cases 32 and 33 are the proof it does not, and they are the reason the extraction is allowed to
# have happened at all.
#
# CC_FIRE_CAPACITY_LIB is the seam that makes this testable: honoured VERBATIM and never folded into
# the fallback list, exactly as CC_FIRE_SYSCTL is (P5). Pointing it at a nonexistent path is the
# only way to reproduce absence — the script-relative candidate resolves through the checkout, so
# HOME and CLAUDE_CONFIG_DIR cannot make the library unreachable (the same discovery
# capacity-admit-coverage.bats case 24c records for the Agent hook, where the remedy was isolation).
#
# RED-PROOF (recorded 2026-08-07, re-runnable): this whole file was replayed against the pristine
# pre-change tree recovered via `git archive 07f9707c` (5888 lines, 0 occurrences of `cc_hw_`), run
# from that tree's OWN root so REPO/HF/LIB all resolve pre-change — one tree per side, never a mix.
# 8 of 43 went RED there, 0 skips either side, so nothing below passes vacuously:
#   32, 33   the absence branch and the wiring do not exist pre-change (32 REFUSES with exit 9 —
#            the pristine gate ignores CC_FIRE_CAPACITY_LIB and measures the stubbed saturated box,
#            which is the fail-CLOSED outcome these cases exist to forbid).
#   P1       the composed extract carries no `cc_hw_resolve_sysctl` — the terms are still inline.
#   P2/P4/P5 red BECAUSE P1 is: the new `gate_reads` matches nothing in the pristine body, so the
#            fragment they execute is the source line alone. That is the intended reading and P1 is
#            what makes it legible — a P2 red with P1 GREEN would mean the PATH bug is back, and a
#            P2 red with P1 red means the extractor is pointed at the wrong tree. Do not read one
#            without the other (memory `wrong-cause-corroborated-by-true-metric`).
#   P6/P8    `cc_hw_resolve_sysctl` is not extractable from the pristine library, and the ncpu read
#            is not in it either — P8's non-vacuity guard is what catches that.
# GREEN ON BOTH TREES BY DESIGN, and each would be a defect otherwise: case 9 (its grep was anchored
# to non-comment position — a robustness fix to a guard a comment could convict, not a new property)
# and case 31 (a STANDING property both trees satisfy; its `>=9` admitting returns read 9 pre-change
# and 10 after, the tenth being the absence branch).

@test "32 an ABSENT library ADMITS, loudly and on the record — never a fleet-wide refusal" {
  # A SATURATED box and a missing library at once. The load term would refuse if it ran, so an
  # admit here can only be the absence branch — on a quiet box this case would pass vacuously.
  run env STUB_NCPU=10 STUB_LOAD=27.16 CC_FIRE_CAPACITY_LIB=/nonexistent/capacity-admit.sh \
      bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -ne 9 ]
  echo "$output" | grep -q 'capacity-admit: ABSENT' || { echo "silent ungated fire: $output"; false; }
  # ...and it is FILED as `absent`, not left as a bare admit: §12.2's rule is that inertness must be
  # LOUD, and §9.5.1's is that you split on `basis` before believing any ratio from these rows. An
  # ungated window counted as `measured` is the population defect both of them name.
  if command -v jq >/dev/null 2>&1; then
    run bash -c "jq -rc 'select(.gate==\"capacity\")|[.verdict,.basis]|@tsv' '$HOME/.claude/logs/handoffs.jsonl'"
    [ "$output" = "$(printf 'admit\tabsent')" ]
  fi
  # POSITIVE CONTROL — the override is what caused the admit. The IDENTICAL fire with the library
  # reachable refuses, so case 32 is testing absence and not a stub that quietly stopped working.
  # Fired LAST: it writes a refusal row, and the jq assertion above is an exact match on the log.
  run env STUB_NCPU=10 STUB_LOAD=27.16 bash "$HF" --prompt-file "$PAYLOAD" --dry-run
  [ "$status" -eq 9 ]
}

@test "33 the gate is WIRED to the library it sources — absence is the only ungated path" {
  # Case 32 proves the absence branch is safe. This proves the PRESENT branch is real: that the
  # terms capacity_gate runs are the library's, not a surviving private copy that would make the
  # extraction cosmetic and case 32's admit meaningless.
  grep -q 'cc_hw_load_verdict' "$HF"     || { echo "capacity_gate does not use the shared load term"; false; }
  grep -q 'cc_hw_headroom_gb' "$HF"      || { echo "capacity_gate does not use the shared headroom term"; false; }
  grep -q 'cc_hw_resolve_sysctl' "$HF"   || { echo "capacity_gate does not use the shared resolver"; false; }
  # and it must READY-CHECK before using any of them, or the absence branch is unreachable
  grep -q 'cc_hw_ready' "$HF"            || { echo "no readiness check — absence would be a crash"; false; }
  # THE ORDER IS THE PROPERTY: the kill switch answers first (an operator who turned the gate off
  # gets silence, not a complaint about a library it was never going to use), then absence, then
  # any term. A readiness check placed after the first term would crash before reaching itself.
  local body offline absent firstterm
  body="$(awk '/^capacity_gate\(\) \{/{p=1} p{print} p&&/^\}$/{exit}' "$HF")"
  offline="$(printf '%s\n' "$body" | grep -n 'CC_FIRE_CAPACITY_GATE' | head -1 | cut -d: -f1)"
  absent="$(printf '%s\n' "$body" | grep -n 'cc_hw_ready' | head -1 | cut -d: -f1)"
  firstterm="$(printf '%s\n' "$body" | grep -n 'cc_hw_resolve_sysctl' | head -1 | cut -d: -f1)"
  # Three separate assertions, NOT `[ -n "$a" ] && [ -n "$b" ]` on one line: that mid-test form is
  # the dead assertion errexit cannot reach in bats, and it is exactly what let capacity-admit-
  # coverage.bats case 26 compare "" to "" and call it parity.
  [ -n "$offline" ]   || { echo "order probe: no kill switch found"; false; }
  [ -n "$absent" ]    || { echo "order probe: no readiness check found"; false; }
  [ -n "$firstterm" ] || { echo "order probe: no term found"; false; }
  [ "$offline" -lt "$absent" ] || { echo "the kill switch must answer before the absence branch"; false; }
  [ "$absent" -lt "$firstterm" ] || { echo "readiness must be checked before the first term runs"; false; }
}

# ── THE LOAD TERM IS PATH-INDEPENDENT BY CONSTRUCTION (item 02ae8ae886a1, 2026-08-06) ────────────
# Everything above proves the gate REASONS correctly once it has numbers. None of it could see that
# in production it never got any. Measured in ~/.claude/logs/handoffs.jsonl over 2026-08-03..06: of
# the 239 rows written with the gate ON, 222 read `hw.ncpu unreadable ('') — load term not
# evaluated` and 17 carried numbers. The whole suite was green throughout, because setup() put a
# `sysctl` stub on PATH and thereby answered the one question production was failing.
#
# That is the trap this section closes: a fixture that supplies the very thing whose ABSENCE is the
# bug can only ever pass (memory hermetic-home-routes-tests-into-the-fallback). These cases run with
# NO stub and NO CC_FIRE_SYSCTL, on a PATH with /usr/sbin removed — the production shape — so they
# exercise the DEFAULT resolution rather than the seam.
#
# Each pair is a test plus its RED CONTROL. The control is not decoration: if /usr/sbin ever joins
# the minimal PATH, the positive case would pass for a reason that has nothing to do with the fix,
# and only a control that FAILS can tell us so (memory control-must-replay-the-real-artifact).

# The exact PATH shape from the repro: /usr/bin and /bin present, /usr/sbin absent.
NOSBIN_PATH="/usr/local/bin:/usr/bin:/bin"

# Extract the resolver + reads straight out of the shipping code, so this tests the real thing
# rather than a restatement of it that can agree with itself while production disagrees.
#
# COMPOSED SINCE THE EXTRACTION: the resolver and both probes moved to scripts/lib/capacity-admit.sh
# and capacity_gate() now CALLS them, so the fragment under test is `source the library` + `the
# gate's own read block`. Testing either half alone would re-create the paraphrase this section
# exists to forbid — the production question was never "does the resolver work", it was "does what
# capacity_gate actually runs resolve sysctl on a /usr/sbin-less PATH", and only the composition
# answers it.
gate_reads() {
  printf '. "%s"\n' "$REPO/scripts/lib/capacity-admit.sh"
  awk '/^capacity_gate\(\) \{/{p=1} p{print} p&&/^\}$/{exit}' "$REPO/scripts/handoff-fire.sh" \
    | sed -n '/sysctl_bin="\$(cc_hw_resolve_sysctl/,/^  ceiling=/p' \
    | grep -v '^  ceiling='
}

@test "P1 the composition is extractable — the cases below test code, not a paraphrase" {
  # If this drifts, P2/P4/P5 would silently test an empty string and pass vacuously.
  run gate_reads
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'CC_FIRE_SYSCTL' || { echo "no override read in the extract"; false; }
  echo "$output" | grep -q 'cc_hw_resolve_sysctl' || { echo "no resolver call in the extract"; false; }
  echo "$output" | grep -q 'cc_hw_ncpu' || { echo "no ncpu read in the extract"; false; }
  # …and the half that MOVED must still carry the absolute default and the sysctl key it resolves.
  # Asserted separately rather than folded in: if the library stopped shipping either, P2/P4 would
  # go red for a reason that reads like a PATH regression and is not (memory
  # `wrong-cause-corroborated-by-true-metric`).
  [ -f "$LIB" ] || { echo "the library the extract sources does not exist — every case below is vacuous"; false; }
  grep -q '/usr/sbin/sysctl' "$LIB" || { echo "no absolute default in the library"; false; }
  grep -q 'hw.ncpu' "$LIB" || { echo "no ncpu read in the library"; false; }
}

@test "P2 hw.ncpu reads a REAL core count with /usr/sbin off the PATH — the production shape" {
  run env -i PATH="$NOSBIN_PATH" HOME="$BATS_TEST_TMPDIR/home" bash -c '
    '"$(gate_reads)"'
    echo "ncpu=[$ncpu] load=[$load]"'
  [ "$status" -eq 0 ]
  # A number, not the empty string that 222 production rows recorded.
  echo "$output" | grep -qE 'ncpu=\[[0-9]+\]' || { echo "got: $output"; false; }
  # Negated form, NOT `A && { …; false; }`: under errexit the `&&` shape passes on both branches
  # once anything absorbs it, which is precisely the dead-assertion class the bats-assert-liveness
  # ratchet exists to catch — and it caught this line, in a suite written to catch a dead gate.
  ! echo "$output" | grep -q 'ncpu=\[\]' || { echo "STILL EMPTY — the bug is not fixed: $output"; false; }
}

@test "P3 RED CONTROL: the SAME reads by BARE NAME really do come back empty on that PATH" {
  # This is the pre-fix code, verbatim, on the same PATH. If it ever passes, /usr/sbin joined the
  # minimal PATH and P2 proves nothing — a control that cannot fail is not a control.
  run env -i PATH="$NOSBIN_PATH" HOME="$BATS_TEST_TMPDIR/home" bash -c '
    ncpu="$(sysctl -n hw.ncpu 2>/dev/null || true)"
    echo "ncpu=[$ncpu]"'
  [ "$output" = "ncpu=[]" ] || {
    echo "the bare-name read RESOLVED on a /usr/sbin-less PATH: $output"
    echo "PATH=$NOSBIN_PATH — if /usr/sbin is now reachable here, P2 is vacuous."; false; }
}

@test "P4 vm.loadavg is PATH-independent too — one binary, both reads, one resolver" {
  # hw.ncpu is the row that surfaced in the ledger only because it is checked FIRST; vm.loadavg is
  # the same sysctl and was equally dead. Fixing one and not the other would move the fail-open
  # string rather than remove it.
  run env -i PATH="$NOSBIN_PATH" HOME="$BATS_TEST_TMPDIR/home" bash -c '
    '"$(gate_reads)"'
    echo "load=[$load]"'
  echo "$output" | grep -qE 'load=\[[0-9]+\.[0-9]+\]' || { echo "got: $output"; false; }
}

@test "P5 an EXPLICIT CC_FIRE_SYSCTL is honoured VERBATIM, never folded into the fallback" {
  # The override must win even when /usr/sbin/sysctl exists and is perfectly good — that is what
  # makes it an override rather than one more entry in a preference list, and it is what keeps this
  # suite's own stub authoritative (memory path-resolved-dependency-in-daemon-code).
  cat > "$BIN/sysctl-explicit" <<'EOF'
#!/bin/bash
case "$*" in *hw.ncpu*) echo 777 ;; *) echo "{ 1.00 1.00 1.00 }" ;; esac
EOF
  chmod +x "$BIN/sysctl-explicit"
  run env -i PATH="$NOSBIN_PATH" HOME="$BATS_TEST_TMPDIR/home" \
      CC_FIRE_SYSCTL="$BIN/sysctl-explicit" bash -c '
    '"$(gate_reads)"'
    echo "ncpu=[$ncpu]"'
  [ "$output" = "ncpu=[777]" ] || { echo "override not honoured verbatim: $output"; false; }
}

@test "P6 the fallback still exists — an absent /usr/sbin/sysctl degrades to the bare name" {
  # The default must not become a hard dependency on one absolute path: a box without
  # /usr/sbin/sysctl should still try, not die.
  #
  # AGAINST THE SHIPPED FUNCTION, not a retyped copy of it. Both halves of this case used to be
  # hand-written restatements of the resolver — which is the one thing this whole section calls a
  # defect, and it was only ever done because the resolver was inline and its `/usr/sbin` literal
  # could not be varied. Now it is a function, so the DEGRADE branch is reached by replaying the
  # real body with that one constant mutated (memory `control-must-replay-the-real-artifact`).
  local body
  body="$(awk '/^cc_hw_resolve_sysctl\(\)/{p=1} p{print} p&&/^\}$/{exit}' "$LIB")"
  [ -n "$body" ] || { echo "cc_hw_resolve_sysctl not extractable — the extractor, not the resolver, is broken"; false; }
  run env -u CC_FIRE_SYSCTL bash -c "$(printf '%s' "$body" | sed 's#/usr/sbin/sysctl#/nonexistent/sysctl#g')
    cc_hw_resolve_sysctl \"\${CC_FIRE_SYSCTL:-}\""
  [ "$output" = "sysctl" ]
  # ...and the SAME function with the real path present picks the absolute one, so P6 proves the
  # fallback is a fallback rather than the branch that always runs.
  run env -u CC_FIRE_SYSCTL bash -c '. "$1"; cc_hw_resolve_sysctl "${CC_FIRE_SYSCTL:-}"' _ "$LIB"
  [ "$output" = "/usr/sbin/sysctl" ]
}

@test "P7 vm_stat's bare name is DELIBERATE — /usr/bin is reachable where /usr/sbin is not" {
  # The header claims vm_stat is safe on its bare name because it lives in /usr/bin. That is a
  # claim about the environment, so it is checked here rather than remembered — this is the test
  # that would go red if the headroom term ever needed the same fix as the load term.
  run env -i PATH="$NOSBIN_PATH" bash -c 'command -v vm_stat'
  [ "$status" -eq 0 ]
  # ...and the asymmetry it rests on: the SAME PATH cannot reach sysctl. One assertion without the
  # other would not establish that /usr/sbin-vs-/usr/bin is the discriminator.
  run env -i PATH="$NOSBIN_PATH" bash -c 'command -v sysctl'
  [ "$status" -ne 0 ]
}

@test "P8 no bare-name sysctl survives in EITHER file — the class, not just the two sites" {
  # An inventory, not a spot-check: a third read added later by bare name would reintroduce exactly
  # this bug and every case above would still pass (memory inventory-before-building).
  #
  # THE INVENTORY FOLLOWS THE CODE. Scanning only handoff-fire.sh was complete while the reads lived
  # there; after the extraction it would be an inventory of a file that no longer performs any read
  # — green by construction, and blind to the file that does. Both are scanned, so the population
  # matches the subject (memory `caller-census-keyed-on-path-misses-the-name`).
  local hits f
  for f in scripts/handoff-fire.sh scripts/lib/capacity-admit.sh; do
    hits="$(grep -nE '(^|[^/[:alnum:]_-])sysctl[[:space:]]+-n' "$REPO/$f" \
              | grep -v '^\s*[0-9]*:\s*#' | grep -v 'sysctl_bin' || true)"
    [ -z "$hits" ] || { echo "BARE-NAME sysctl read(s) still present in $f:"; echo "$hits"; false; }
  done
  # NOT VACUOUS: the scanned population must actually contain the reads, or two clean files prove
  # nothing. The library is where they went, so that is where they must be found.
  grep -qE '"\$1" -n hw\.ncpu' "$REPO/scripts/lib/capacity-admit.sh" \
    || { echo "the ncpu read is in neither file — P8 is scanning an empty subject"; false; }
}
