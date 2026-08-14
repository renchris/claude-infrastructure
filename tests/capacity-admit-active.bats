#!/usr/bin/env bats
# WAVE D RE-TERM — the admission gate keys on ACTIVE concurrency, with a memory term that can
# actually bind. Backlog 1c45598a91be; DoD docs/research/scaling-bottlenecks-2026-08-09.md §5-P2;
# specified by CONCURRENCY_PROGRAM.md §S6.6 (items 1 and 2) and accepted by its D7 criterion.
#
# THE TWO PROPERTIES UNDER TEST, and why either alone is worthless:
#
#   1. THE MEMORY TERM CAN BIND. §S6.6 measured the incumbent one — `free + speculative + inactive +
#      purgeable >= 4 GB` — firing 0 times in 127 refusals, and it *cannot* bind: it counts dirty
#      anonymous inactive pages as free. Side by side on the quiet box it read 40.55 GB (ADMIT)
#      against segments at 0.00%; AT THE PANIC it read 29.79 GB — still ADMIT — against segments at
#      100%. Case 05 is that measurement replayed as a control: ONE world, the old term admitting and
#      the new one refusing. A segment term that merely EXISTS satisfies the D7 grep and proves
#      nothing, so every refusal case here is paired with the headroom reading that would have
#      admitted it.
#
#   2. THE CEILING IS ON ACTIVITY, NOT RESIDENCY. Axis 13 records the circularity this closes: "≤10
#      active is a property of the system — nothing does [bound it]. The ranking assumes the outcome
#      of the wave its own conclusion deprioritises." Cases 10-13 pin that a MID-TURN population is
#      what is counted: the same fleet size admits or refuses depending only on how many sessions are
#      mid-turn, which is the one thing a residency census cannot express.
#
# HERMETICITY: `sysctl`, `vm_stat` and `ps` are stubbed, HOME/beat dir/budget state/IDL/notifier are
# fixtured under BATS_TEST_TMPDIR, and the clock is pinned. Nothing here reads the mood of the
# machine running the suite, no page can reach the operator, and the suite therefore runs on a Linux
# CI box as well as on the macOS target — which matters, because the two new probes are
# macOS-specific and an untestable term is one that rots.
#
# RED-PROOF (measured 2026-08-13, re-runnable — `git stash push scripts/lib/capacity-admit.sh
# scripts/lib/spawn-presence.sh hooks/agent-teams-enforce.sh`, run, `git stash pop`): 21 of 21 cases
# FAIL against pristine trunk. The segment functions and `cc_sp_active` are undefined there, so the
# gate admits every world these cases refuse; case 17's D7 grep returns 0; case 18 finds no
# explanation of the new terms in the hook.
#
# The first replay found 20 of 21, and the exception is worth recording rather than smoothing over:
# case 15 asserts an ADMIT, which the unfixed gate also produces — for the opposite reason, the term
# not existing at all. A case whose expected verdict is "admit" is satisfied by a DELETED gate, so it
# now also asserts that the row shows the term ran and cleared. A suite that passes against the
# unfixed subject is a suite that tests nothing, and the admit-shaped cases are where that leaks in.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/capacity-admit.sh"
  SP="$REPO/scripts/lib/spawn-presence.sh"
  SENTINEL="$REPO/scripts/compressor-sentinel.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"; mkdir -p "$CC_BEAT_DIR"
  export CC_SP_BEAT_LIB="$REPO/hooks/lib/cc-beat.sh"
  export CC_ADMIT_PRESENCE_LIB="$SP"
  export CC_ADMIT_NOTIFY_BIN="$BATS_TEST_TMPDIR/notify"
  cat > "$CC_ADMIT_NOTIFY_BIN" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/pages.txt"
EOF
  chmod +x "$CC_ADMIT_NOTIFY_BIN"

  # ── the stubbed box ────────────────────────────────────────────────────────────────────────────
  # Every sysctl this gate reads, answered from an env var so a case can move ONE number and leave
  # the rest of the world pinned. The compressor keys are the ones that do not exist off macOS, and
  # stubbing them is what makes the term's arithmetic assertable at all.
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  cat > "$BIN/sysctl" <<'EOF'
#!/bin/bash
case "$*" in
  *hw.ncpu*)                           echo "${STUB_NCPU:-10}" ;;
  *vm.loadavg*)                        echo "{ ${STUB_LOAD:-1.00} ${STUB_LOAD:-1.00} ${STUB_LOAD:-1.00} }" ;;
  *vm.compressor_segment_limit*)       echo "${STUB_SEGLIM:-262144}" ;;
  *vm.compressor_segment_buffer_size*) echo "${STUB_SEGBUF:-65536}" ;;
  *vm.swapusage*)                      echo "total = 8192.00M  used = ${STUB_SWAP:-0.00}M  free = 8192.00M  (encrypted)" ;;
  *) exit 1 ;;
esac
EOF
  # A 16 KiB page size, as on the Apple-silicon target: four pages to a 64 KiB segment. A 4 KiB box
  # needs sixteen, which is exactly why the divisor is derived and never the literal 4 (case 04).
  cat > "$BIN/vm_stat" <<'EOF'
#!/bin/bash
echo "Mach Virtual Memory Statistics: (page size of ${STUB_PGSZ:-16384} bytes)"
echo "Pages free:                          ${STUB_FREE:-2000000}."
echo "Pages speculative:                   0."
echo "Pages inactive:                      0."
echo "Pages purgeable:                     0."
echo "Pages occupied by compressor:        ${STUB_COMPPAGES:-0}."
EOF
  chmod +x "$BIN/sysctl" "$BIN/vm_stat"
  export CC_ADMIT_SYSCTL="$BIN/sysctl"
  export PATH="$BIN:$PATH"
  export CC_BEAT_NOW=1000000 CC_SP_NOW=1000000 CC_SP_HOUR=12
  # Neither of the OLD terms may refuse in this suite unless a case says so: a refusal that could
  # have come from load or headroom would make every assertion below ambiguous about which term
  # fired, and the whole point is which term fired.
  export CC_ADMIT_LOADAVG_OVERRIDE=1.0
  export CC_ADMIT_HEADROOM_OVERRIDE=64
  export CC_SP_TREES_OVERRIDE=3
}

# The gate's rc IS the subshell's rc — deliberately the last statement (capacity-admit.bats records
# why: a helper ending on cc_capacity_admit_reason returns that function's 0 and masks every REFUSE).
admit() { # $1=caller $2=what → prints the reason, exits with the gate's rc
  bash -c '. "$1"; cc_capacity_admit "$2" "$3"; rc=$?; cc_capacity_admit_reason; exit $rc' \
    _ "$LIB" "$1" "${2:-spawn}"
}
sp() { bash -c '. "$1"; shift; "$@"' _ "$SP" "$@"; }
term_of() { jq -r "select(.caller==\"$1\") | .term // \"none\"" "$CC_ADMIT_IDL"; }

# One beat. $1=sid $2=t $3=kind $4=pid $5=lstart ($6=operatorT, optional)
beat() {
  jq -cn --arg sid "$1" --argjson t "$2" --arg k "$3" --argjson pid "$4" --arg ls "$5" \
         --arg op "${6:-}" \
    '{sid:$sid,t:$t,kind:$k,pid:$pid,lstart:$ls,who:"auto",seq:1}
     + (if $op == "" then {} else {operatorT:($op|tonumber), who:"operator"} end)' \
    > "$CC_BEAT_DIR/$1.json"
}

# ══ 1. THE MEMORY TERM THAT CAN BIND ══════════════════════════════════════════════════════════════

@test "01 the segment term REFUSES over the ceiling, and names itself in the row" {
  # 800,000 compressor pages at 16 KiB = 200,000 in-core segments of a 262,144 limit = 76.29%.
  STUB_COMPPAGES=800000 run admit seg-a "spawn"
  [ "$status" -eq 9 ]
  [ "$(term_of seg-a)" = segments ]
  [[ "$output" == *"76.29%"* ]] || false
  # basis stays `measured` on a refusal: the instruments read fine, it is the BOX that is over.
  [ "$(jq -r 'select(.caller=="seg-a") | .basis' "$CC_ADMIT_IDL")" = measured ]
}

@test "02 CONTROL — the same box under the ceiling ADMITS, and the pct rides on the admit row" {
  # 200,000 pages = 50,000 segments = 19.07%. §9.5.1: an admit with no numbers is worse than a
  # refusal with none, and this row is also what makes the provisional 50% ceiling re-derivable.
  STUB_COMPPAGES=200000 run admit seg-b "spawn"
  [ "$status" -eq 0 ]
  [[ "$output" == *"segments 19.07% of limit"* ]] || false
}

@test "03 SWAPPED-OUT segments count — they hold their descriptor against the same limit" {
  # The 2026-07-30 panic hit 100% of the SEGMENT limit at 33% of the compressed-PAGES limit. A term
  # counting only resident segments would under-read exactly the state it exists to see. 12 GB of
  # swap at 64 KiB per chunk is 196,608 segments = 75% of the limit on its own, with ZERO pages in
  # core — so only the swap arm can produce this refusal. (8 GB lands on exactly 50.00%, which the
  # verdict admits: the comparison is strictly `>`, and a case sitting on a boundary tests the
  # boundary rather than the arm it names.)
  STUB_COMPPAGES=0 STUB_SWAP=12288.00 run admit seg-c "spawn"
  [ "$status" -eq 9 ]
  [ "$(term_of seg-c)" = segments ]
  # ...and the control that proves the swap arm is what fired: same box, no swap.
  STUB_COMPPAGES=0 STUB_SWAP=0.00 run admit seg-d "spawn"
  [ "$status" -eq 0 ]
}

@test "04 the divisor is DERIVED from the page size — a 4 KiB box is not read 4x low" {
  # Same 800,000 pages, but at 4 KiB each: 800000/(65536/4096) = 50,000 segments = 19.07%, NOT the
  # 76.29% of case 01. A hardcoded /4 would refuse here, which is the 4x error in the other
  # direction from the one cc_hw_headroom_gb's header documents.
  STUB_PGSZ=4096 STUB_COMPPAGES=800000 run admit seg-e "spawn"
  [ "$status" -eq 0 ]
  [[ "$output" == *"segments 19.07% of limit"* ]] || false
}

@test "05 THE DoD CONTROL — the world §S6.6 measured: headroom ADMITS while segments REFUSE" {
  # This is the case the item exists for. At the panic the incumbent term read 29.79 GB reclaimable
  # and admitted, with segments at 100%. Both terms are given their real inputs over ONE world, and
  # they must disagree — otherwise the new term is decorative and the gate still cannot bind on
  # memory. `STUB_FREE` drives the OLD term (2,000,000 pages x 16 KiB = 30.5 GB, comfortably over
  # the 4 GB floor), so the override that pins it elsewhere in this suite is removed here.
  run env -u CC_ADMIT_HEADROOM_OVERRIDE STUB_FREE=2000000 STUB_COMPPAGES=1048576 \
    bash -c '. "$1"; cc_capacity_admit dod "spawn"; rc=$?; cc_capacity_admit_reason; exit $rc' _ "$LIB"
  [ "$status" -eq 9 ]
  [ "$(term_of dod)" = segments ]
  [[ "$output" == *"100.00%"* ]] || false
  # The old term, alone, over the SAME world: admits. Without this half the case above is satisfied
  # by any gate that refuses everything.
  run env -u CC_ADMIT_HEADROOM_OVERRIDE STUB_FREE=2000000 STUB_COMPPAGES=1048576 \
    bash -c 'CC_ADMIT_SEGMENT_TERM=off CC_ADMIT_ACTIVE_TERM=off
             . "$1"; cc_capacity_admit dod2 "spawn"; rc=$?; cc_capacity_admit_reason; exit $rc' _ "$LIB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reclaimable 30."* ]] || false
}

@test "06 ARITHMETIC PARITY — this term and compressor-sentinel.sh agree on one fixture" {
  # The gate is a THIRD reader of vm_stat, which the library's header defends on the grounds that a
  # gate, a monitor and a daemon are different instruments. What must NOT differ is the arithmetic,
  # and the sentinel is the reference implementation (§7.7). A literal comparison would say nothing
  # about the ten other lines, so both real implementations are RUN over one input.
  local segs_ref pct_mine
  segs_ref="$(bash -c '
      eval "$(awk "/^segs_in_core\\(\\) \\{/,/^\\}/" "$1")"
      eval "$(awk "/^segs_swapped\\(\\) \\{/,/^\\}/" "$1")"
      i=$(segs_in_core 800000 16384 65536); s=$(segs_swapped 268435456 65536)
      echo $(( i + s ))' _ "$SENTINEL")"
  # 200,000 in-core + 4,096 swapped
  [ "$segs_ref" = "204096" ]
  pct_mine="$(STUB_COMPPAGES=800000 STUB_SWAP=256.00 bash -c \
    '. "$1"; cc_hw_compressor_segment_pct "$2"' _ "$LIB" "$CC_ADMIT_SYSCTL")"
  [ "$(printf '%s' "$pct_mine" | awk '{print $2}')" = "$segs_ref" ]
}

@test "07 an unreadable segment probe is a NOTED blindness, never a deleted gate" {
  # THE structural rule for a term added after the fact: failing open out of the function would
  # delete the active and reserve terms below it over an input they never asked for. The blindness
  # must instead be visible — a term that silently stopped evaluating reads back as a healthy admit,
  # which is the 222-dead-sysctl-rows shape (item 02ae8ae886a1).
  cat > "$BIN/sysctl" <<'EOF'
#!/bin/bash
case "$*" in
  *hw.ncpu*)    echo 10 ;;
  *vm.loadavg*) echo "{ 1.00 1.00 1.00 }" ;;
  *) exit 1 ;;
esac
EOF
  run admit blind-a "spawn"
  [ "$status" -eq 0 ]
  [[ "$(jq -r 'select(.caller=="blind-a") | .blind' "$CC_ADMIT_IDL")" == *segments* ]] || false
  # ...and the ACTIVE term still ran over the same evaluation. This is the half that proves the
  # blindness was not a return.
  [[ "$(jq -r 'select(.caller=="blind-a") | .terms' "$CC_ADMIT_IDL")" == *active* ]] || false
}

@test "08 the term is switchable, and switching it off is recorded rather than silent" {
  STUB_COMPPAGES=1048576 run bash -c 'CC_ADMIT_SEGMENT_TERM=off; . "$1"; cc_capacity_admit seg-off "s"' _ "$LIB"
  [ "$status" -eq 0 ]
  [ "$(jq -r 'select(.caller=="seg-off") | .terms' "$CC_ADMIT_IDL")" = "load,headroom,active" ]
}

@test "09 a segment refusal is BOUNDED — it releases and pages, like every other term" {
  # §9's narrowed law applies to a term added later exactly as it does to the two that were here
  # first: an unbounded refusal on an actuation path IS the §12.2 outage.
  local rcs=""
  for i in 1 2; do
    # EXPORTED, not merely assigned: STUB_COMPPAGES is read by the `vm_stat` stub, which is a CHILD
    # process. A bare assignment leaves the stub on its default of 0 and the case then asserts a
    # bound over a box that was never over the ceiling — it would have passed for the wrong reason
    # in the other direction, which is how a bound test goes vacuous.
    # The iteration rides into `what`, so the two evaluations are distinguishable in the ledger —
    # the same shape tests/capacity-admit.bats case 04 uses. A loop counter this case never spends
    # is also what SC2034 flags, and naming the spawn is the fix that leaves the assertion stronger
    # rather than the warning silenced.
    run bash -c 'export CC_ADMIT_BUDGET=1 STUB_COMPPAGES=1048576; . "$1"; cc_capacity_admit seg-bd "s$2"' _ "$LIB" "$i"
    rcs="$rcs$status,"
  done
  [ "$rcs" = "9,0," ]
  grep -q "spent its 1-refusal budget" "$BATS_TEST_TMPDIR/pages.txt"
}

# ══ 2. THE ACTIVE-CONCURRENCY CEILING ═════════════════════════════════════════════════════════════

@test "10 the census counts MID-TURN sessions only — a stop beat is not activity" {
  local ls; ls="$(ps -o lstart= -p $$ | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  beat a 999990 prompt "$$" "$ls"
  beat b 999985 stop   "$$" "$ls"
  [ "$(sp cc_sp_active)" = 1 ]
}

@test "11 a session that DIED mid-turn is not counted — identity is (pid,lstart)" {
  # The failure this exists to prevent is monotonic: a crash leaves its `kind:"prompt"` beat on disk
  # forever, so a census over beats alone would refuse a little more with every crash until the
  # ceiling became unreachable. Two halves: a pid that is gone, and a pid that is ALIVE but whose
  # lstart differs — the recycled-pid case, which a liveness check on pid alone cannot see.
  local ls; ls="$(ps -o lstart= -p $$ | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  beat live 999990 prompt "$$" "$ls"
  beat dead 999989 prompt 999999 "Tue Aug 12 10:00:00 2026"
  beat recy 999988 prompt "$$" "Mon Jan  1 00:00:00 2001"
  [ "$(sp cc_sp_active)" = 1 ]
}

@test "11b two mid-turn beats resolving to ONE claude ancestor count as ONE active unit" {
  # session-beat.sh walks up to the nearest claude/claude.exe process, and subagents share their
  # lead's — so a row-count would report two ACTIVE units for one session tree. cc_sp_trees one
  # function above already carries this correction (it skips a process whose parent is in-family);
  # the active census has to make it too, and in the same direction: a duplicate is not evidence of
  # a second concurrent turn.
  local ls; ls="$(ps -o lstart= -p $$ | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  beat lead 999990 prompt "$$" "$ls"
  beat sub  999989 prompt "$$" "$ls"
  [ "$(sp cc_sp_active)" = 1 ]
}

@test "12 the ACTIVE term REFUSES at the ceiling and ADMITS one below it" {
  CC_SP_ACTIVE_OVERRIDE=8 CC_ADMIT_ACTIVE_CEILING=8 run admit act-a "spawn"
  [ "$status" -eq 9 ]
  [ "$(term_of act-a)" = active ]
  [[ "$output" == *"8 sessions mid-turn + 1 > active ceiling 8"* ]] || false
  CC_SP_ACTIVE_OVERRIDE=7 CC_ADMIT_ACTIVE_CEILING=8 run admit act-b "spawn"
  [ "$status" -eq 0 ]
}

@test "13 THE DoD CONTROL — ACTIVITY decides, not RESIDENCY: one fleet size, two verdicts" {
  # The property the whole item turns on. Residency is held CONSTANT at 40 trees (well under the
  # measured 54 ceiling, so the resident term cannot be what fires) and only the mid-turn count
  # moves. A gate that still keyed on residency would return the same verdict twice.
  CC_SP_TREES_OVERRIDE=40 CC_SP_ACTIVE_OVERRIDE=9 run admit mix-a "spawn"
  [ "$status" -eq 9 ]
  [ "$(term_of mix-a)" = active ]
  CC_SP_TREES_OVERRIDE=40 CC_SP_ACTIVE_OVERRIDE=2 run admit mix-b "spawn"
  [ "$status" -eq 0 ]
}

@test "14 reserve-active yields ONE slot to a PRESENT operator, and never to self" {
  # Same law as reserve-headroom, in the dimension that binds first. Three worlds, identical but for
  # who is spawning: autonomy while the operator is at the keyboard REFUSES; the operator's own
  # session over the same world ADMITS; and the terms stay distinguishable, because `active` means
  # the box is out while `reserve-active` means it had room and autonomy yielded.
  beat s1 999940 stop 1 x 999940
  CC_SP_ACTIVE_OVERRIDE=7 CC_ADMIT_ACTIVE_CEILING=8 run admit res-a "spawn"
  [ "$status" -eq 9 ]
  [ "$(term_of res-a)" = reserve-active ]
  [[ "$output" == *"operator reserve 1"* ]] || false
  CC_ADMIT_SID=s1 CC_SP_ACTIVE_OVERRIDE=7 CC_ADMIT_ACTIVE_CEILING=8 run admit res-b "spawn"
  [ "$status" -eq 0 ]
  [ "$(jq -r 'select(.caller=="res-b") | .presence' "$CC_ADMIT_IDL")" = self ]
}

@test "15 an ABSENT operator carries NO base active reserve — protection is added on PROVEN presence" {
  # Unlike the slot reserve (base 2), this term is already the tightest on the gate; a standing base
  # would permanently spend an eighth of the design point on a human who is provably not there.
  beat s1 999990 stop 1 x 992800          # beat system live, no fresh operator turn ⇒ absent
  CC_SP_ACTIVE_OVERRIDE=7 CC_ADMIT_ACTIVE_CEILING=8 run admit res-c "spawn"
  [ "$status" -eq 0 ]
  [ "$(jq -r 'select(.caller=="res-c") | .presence' "$CC_ADMIT_IDL")" = absent ]
  # THE ADMIT MUST BE THE TERM'S, NOT ITS ABSENCE. This is the one case here whose verdict a gate
  # with NO active term also produces, so without the next two lines it passes against the unfixed
  # subject — a green that means "the feature is missing" (measured: it was the single case that
  # survived the pristine-trunk replay). The row must show the term ran and cleared at 7 of 8.
  [[ "$(jq -r 'select(.caller=="res-c") | .detail' "$CC_ADMIT_IDL")" == *"7 sessions mid-turn (active ceiling 8)"* ]] || false
  [[ "$(jq -r 'select(.caller=="res-c") | .terms' "$CC_ADMIT_IDL")" == *active* ]] || false
}

@test "16 an unreadable ACTIVE census is a NOTED blindness, and the other terms still run" {
  # Same rule as case 07, from the other side: `ps` refuses, so the census cannot prove liveness for
  # any candidate. The positive control in cc_sp_active is what makes that rc 1 rather than a
  # fabricated 0 — without it a dead `ps` reads as an empty fleet, i.e. infinite headroom.
  local ls; ls="$(ps -o lstart= -p $$ | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  beat a 999990 prompt "$$" "$ls"
  cat > "$BATS_TEST_TMPDIR/psfail" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$BATS_TEST_TMPDIR/psfail"
  mkdir -p "$BATS_TEST_TMPDIR/psbin"; cp "$BATS_TEST_TMPDIR/psfail" "$BATS_TEST_TMPDIR/psbin/ps"
  run env -u CC_SP_ACTIVE_OVERRIDE PATH="$BATS_TEST_TMPDIR/psbin:$PATH" \
    bash -c '. "$1"; cc_capacity_admit blind-b "spawn"' _ "$LIB"
  [ "$status" -eq 0 ]
  [[ "$(jq -r 'select(.caller=="blind-b") | .blind' "$CC_ADMIT_IDL")" == *active* ]] || false
  [[ "$(jq -r 'select(.caller=="blind-b") | .detail' "$CC_ADMIT_IDL")" == *"segments"* ]] || false
}

# ══ 3. THE ACCEPTANCE CRITERION AND THE WIRING ════════════════════════════════════════════════════

@test "17 D7 — the criterion CONCURRENCY_PROGRAM.md publishes for this wave" {
  # "Wave D decided — admission keys on ACTIVE concurrency and the memory term can actually bind":
  # `grep -c compressor_segment scripts/lib/capacity-admit.sh` > 0, or a recorded waiver. The probe
  # is quoted verbatim from the criterion rather than paraphrased, so this case cannot pass against a
  # different question than the one the program asked.
  [ "$(grep -c compressor_segment "$LIB")" -gt 0 ]
  # ...and the half the grep cannot see: the term is REACHED by the gate, not merely defined. A
  # criterion satisfiable by a definition nothing calls is the inertness generator in one line.
  grep -q 'cc_hw_compressor_segment_pct "\$sysctl_bin"' "$LIB"
  grep -q 'cc_sp_active' "$LIB"
}

@test "18 the Agent tool — the highest-volume spawn surface — inherits BOTH new terms" {
  # It turns the LOAD term off deliberately and must not turn these off with it: axis 10's F3 is a
  # fan-out while other sessions are mid-turn, which is precisely this path.
  local call
  call="$(awk '/^if command -v cc_capacity_admit/,/^  fi$/' "$REPO/hooks/agent-teams-enforce.sh")"
  [ -n "$call" ] || { echo "the capacity call site was not found — the extractor is broken"; false; }
  [[ "$call" != *"CC_ADMIT_SEGMENT_TERM=off"* ]] || { echo "the Agent path disables the segment term"; false; }
  [[ "$call" != *"CC_ADMIT_ACTIVE_TERM=off"* ]]  || { echo "the Agent path disables the active term"; false; }
  # A refusal naming a term the reader cannot interpret is a refusal that gets overridden blindly, so
  # the hook's explanation must cover the new names as it covers the old ones.
  [[ "$call" == *"\`active\` means"* ]] || false
  [[ "$call" == *"\`segments\` means"* ]] || false
}

@test "19 EVERY TERM OFF is gate-off; the OLD pair off with a Wave D term on is NOT" {
  # The §9.5.1 population defect, in both directions. Recording a real segment/active evaluation as
  # `gate-off` would count a live refusal-capable window as a blind one — the same error the
  # two-term branch was written to prevent, arriving from the other side.
  run bash -c 'CC_ADMIT_LOAD_TERM=off CC_ADMIT_HEADROOM_TERM=off
               . "$1"; cc_capacity_admit pair-off "s"' _ "$LIB"
  [ "$status" -eq 0 ]
  [ "$(jq -r 'select(.caller=="pair-off") | .basis' "$CC_ADMIT_IDL")" != gate-off ]
  [ "$(jq -r 'select(.caller=="pair-off") | .terms' "$CC_ADMIT_IDL")" = "segments,active" ]
  # ...and with all four off it IS gate-off, evaluating nothing.
  run bash -c 'CC_ADMIT_LOAD_TERM=off CC_ADMIT_HEADROOM_TERM=off CC_ADMIT_SEGMENT_TERM=off CC_ADMIT_ACTIVE_TERM=off
               . "$1"; cc_capacity_admit all-off "s"' _ "$LIB"
  [ "$(jq -r 'select(.caller=="all-off") | .basis' "$CC_ADMIT_IDL")" = gate-off ]
}

@test "20 a dead sysctl no longer deletes the terms that never asked about it" {
  # 222 of 239 capacity rows over 2026-08-03..06 read `hw.ncpu unreadable ('')` because /usr/sbin is
  # absent from a launchd PATH. With two terms that fail-open return was defensible; with four it is
  # a deletion — and on the Agent-tool path, which turns the load term OFF, it deleted the whole gate
  # over an input that path does not use. Here the load term is off and hw.ncpu is unreadable: the
  # segment term must still refuse.
  cat > "$BIN/sysctl" <<'EOF'
#!/bin/bash
case "$*" in
  *hw.ncpu*|*vm.loadavg*)              exit 1 ;;
  *vm.compressor_segment_limit*)       echo 262144 ;;
  *vm.compressor_segment_buffer_size*) echo 65536 ;;
  *vm.swapusage*)                      echo "total = 8192.00M  used = 0.00M  free = 8192.00M  (encrypted)" ;;
  *) exit 1 ;;
esac
EOF
  run env -u CC_ADMIT_LOADAVG_OVERRIDE STUB_COMPPAGES=1048576 \
    bash -c 'CC_ADMIT_LOAD_TERM=off; . "$1"; cc_capacity_admit deadctl "s"' _ "$LIB"
  [ "$status" -eq 9 ]
  [ "$(term_of deadctl)" = segments ]
  # CONTROL: with the load term ON, an unreadable hw.ncpu still fails the gate open, unchanged.
  run env -u CC_ADMIT_LOADAVG_OVERRIDE \
    bash -c '. "$1"; cc_capacity_admit deadctl2 "s"' _ "$LIB"
  [ "$status" -eq 0 ]
  [ "$(jq -r 'select(.caller=="deadctl2") | .basis' "$CC_ADMIT_IDL")" = fail-open ]
}

@test "21 rows stay slurpable and every one carries terms (the population split)" {
  # ONE malformed line aborts the cc-audit `jq -rs` slurp, which then reads as "no records" and
  # silently flips the abstain alarm GREEN. The new fields are jq-encoded like every other.
  bash -c '. "$1"; cc_capacity_admit t21 "$(printf '"'"'a"b\nc\\d'"'"')"' _ "$LIB" >/dev/null
  run jq -rs 'length' "$CC_ADMIT_IDL"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  [ "$(jq -rs 'map(select(.terms == null)) | length' "$CC_ADMIT_IDL")" = "0" ]
}
