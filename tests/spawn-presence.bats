#!/usr/bin/env bats
# scripts/lib/spawn-presence.sh + the reserve term it feeds — BACKLOG_SELF_DRAINING §W3
# (backlog 8ae4b508f274).
#
# THE DoD IS ONE CASE AND IT IS CASE 20. Everything else here exists to stop that case passing for a
# wrong reason: "with the operator active, unattended spawns YIELD — demonstrated by a capacity
# refusal that hits an autonomy path rather than a /handoff." So case 20 drives BOTH gates over ONE
# pinned world and asserts they disagree — autonomy refused, the operator's fire admitted — because
# either half alone is satisfiable by a gate that simply refuses everything or admits everything.
#
# RED-PROOF DISCIPLINE (the predecessor's cost, restated so it is not paid twice): a harness that
# extracted `live_workers` without its helper `is_uint` made every case return UNKNOWN and pass
# VACUOUSLY — against the BROKEN binary too. So every case here runs the REAL library from the repo
# (never an extracted fragment), and every REFUSE case has a paired control that must ADMIT. The
# recorded pristine-trunk RED-proof is in § RED-PROOF at the bottom of this file.
#
# HERMETICITY: HOME, the beat dir, the budget state, the IDL and the notifier are all fixtured under
# BATS_TEST_TMPDIR, and `ps` is stubbed for the census cases — so no assertion here reads the mood of
# the machine running the suite, and no page can reach the operator.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SP="$REPO/scripts/lib/spawn-presence.sh"
  CA="$REPO/scripts/lib/capacity-admit.sh"
  BEAT="$REPO/hooks/lib/cc-beat.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"
  mkdir -p "$CC_BEAT_DIR"
  export CC_SP_BEAT_LIB="$BEAT"
  export CC_ADMIT_PRESENCE_LIB="$SP"
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_ADMIT_NOTIFY_BIN="$BATS_TEST_TMPDIR/notify"
  cat > "$CC_ADMIT_NOTIFY_BIN" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/pages.txt"
EOF
  chmod +x "$CC_ADMIT_NOTIFY_BIN"
  # A pinned clock and a pinned box. Presence, hour, census, load and headroom are all INPUTS here —
  # an assertion that moves with the machine is not an assertion (M11).
  export CC_BEAT_NOW=1000000
  export CC_SP_NOW=1000000
  export CC_SP_HOUR=12                 # inside the measured 10:00->04:59 operator window
  export CC_ADMIT_LOADAVG_OVERRIDE=1.0
  export CC_ADMIT_HEADROOM_OVERRIDE=64
  export CC_SP_TREES_OVERRIDE=5

  # ── THE CAPACITY PIN, FORM 2 (scripts/test-hermeticity-lint.sh § is_fire_pinned) ────────────────
  # Cases 20, 29 and 30 drive handoff-fire's capacity_gate, so this suite is one of the few whose
  # SUBJECT is that gate — and form 1, `CC_FIRE_CAPACITY_GATE=off`, is unavailable BY CONSTRUCTION
  # here: pinning the gate off deletes the only thing those cases test. Form 2 reaches the property
  # the rule actually protects (the gate cannot read AMBIENT machine load) by closing both paths the
  # real box uses: CC_FIRE_SYSCTL makes load and core count stub output, CC_FIRE_HEADROOM_OVERRIDE
  # makes the memory term a literal. Those fires are then exactly as load-insensitive as form 1's,
  # with the coverage intact. Individual cases still override per-case; an explicit override wins.
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  cat > "$BIN/sysctl" <<'EOF'
#!/bin/bash
case "$*" in
  *hw.ncpu*)    echo "${STUB_NCPU:-10}" ;;
  *vm.loadavg*) echo "{ ${STUB_LOAD:-1.00} ${STUB_LOAD:-1.00} ${STUB_LOAD:-1.00} }" ;;
  *)            exit 1 ;;
esac
EOF
  chmod +x "$BIN/sysctl"
  export CC_FIRE_SYSCTL="$BIN/sysctl"
  export CC_FIRE_HEADROOM_OVERRIDE=64
  # THE NON-$HOME SEAMS (lint rule 5a/5b): fixturing $HOME does not redirect an ABSOLUTE /tmp default,
  # nor a BARE NAME the subject then EXECUTES off the operator's PATH. An ABSENT path is the right
  # value — these sensors fail open on one — so they point into the tmpdir and nothing else.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export CC_ACCOUNTS_BIN="$BIN/claude-accounts"
}

# Write one beat. $1=sid $2=t $3=operatorT (empty ⇒ field absent, i.e. a pre-v2 beat)
beat() {
  if [ -n "${3:-}" ]; then
    printf '{"sid":"%s","t":%s,"operatorT":%s,"who":"operator","seq":1}\n' "$1" "$2" "$3" > "$CC_BEAT_DIR/$1.json"
  else
    printf '{"sid":"%s","t":%s,"who":"auto","seq":1}\n' "$1" "$2" > "$CC_BEAT_DIR/$1.json"
  fi
}

sp() { bash -c '. "$1"; shift; "$@"' _ "$SP" "$@"; }

# Extract one shell function's text from a script, by NAME. awk, not sed: a sed address containing
# `{` is subject to bash brace expansion at the call site (`{/,/^}` expands to two words), which
# silently handed sed two malformed scripts and made three cases fail for a harness reason. The point
# of extracting at all is that these cases run the REAL function text rather than a copy of it — a
# control that replays a re-implementation proves nothing about the subject
# (memory control-must-replay-the-real-artifact).
extract_fn() { # $1=file $2=fn-name...
  local f="$1"; shift
  local n
  for n in "$@"; do
    awk -v fn="$n" '
      $0 ~ "^" fn "\\(\\) \\{" { on = 1 }
      on { print }
      on && /^\}/ { on = 0 }
    ' "$f"
  done
}

# The gate's rc IS the subshell's rc — deliberately the last statement. capacity-admit.bats records
# why: a helper ending on `cc_capacity_admit_reason` returns that function's 0 and masks every
# REFUSE, and two cases passed a rc-9 assertion against rc 0 until they were actually run.
admit() { # $1=caller $2=what → prints the reason, exits with the gate's rc
  bash -c '. "$1"; cc_capacity_admit "$2" "$3"; rc=$?; cc_capacity_admit_reason; exit $rc' \
    _ "$CA" "$1" "${2:-spawn}"
}

# ══ PRESENCE ═════════════════════════════════════════════════════════════════════════════════════

@test "01 operator typing 60s ago reads PRESENT" {
  beat s1 999940 999940
  [ "$(sp cc_sp_operator_state)" = present ]
}

@test "02 last operator turn beyond the window, beat system live ⇒ ABSENT (a measurement)" {
  # t is fresh (the session is alive and beating) but the human has not driven a turn in 2h.
  beat s1 999990 992800
  [ "$(sp cc_sp_operator_state)" = absent ]
}

@test "03 no beat younger than the live window ⇒ UNKNOWN, never ABSENT (the existence gate)" {
  # The producer's world is not demonstrably producing. Asserting "the operator is absent" from a
  # dead producer is manufacturing a measurement out of nothing.
  beat s1 900000 900000
  [ "$(sp cc_sp_operator_state)" = unknown ]
}

@test "04 empty beat dir ⇒ UNKNOWN" {
  [ "$(sp cc_sp_operator_state)" = unknown ]
}

@test "05 beat library unreachable ⇒ UNKNOWN (absent-tolerant, never a silent tighten)" {
  CC_SP_BEAT_LIB=/nonexistent/cc-beat.sh run sp cc_sp_operator_state
  [ "$output" = unknown ]
}

@test "06 the SPAWNING session's own operator turn reads SELF, and self outranks present" {
  beat s1 999940 999940
  [ "$(sp cc_sp_operator_state s1)" = self ]
}

@test "07 a DIFFERENT session's operator turn is PRESENT for us, not SELF" {
  beat s1 999940 999940
  [ "$(sp cc_sp_operator_state s2)" = present ]
}

@test "08 a torn beat file cannot forge presence — the slurp fails ⇒ UNKNOWN" {
  beat s1 999940 999940
  printf '{"sid":"s2","t":' > "$CC_BEAT_DIR/s2.json"
  [ "$(sp cc_sp_operator_state)" = unknown ]
}

@test "09 a clock that stepped backwards clamps to PRESENT, never to a forged long absence" {
  beat s1 1000500 1000500
  [ "$(sp cc_sp_operator_state)" = present ]
}

# ══ THE MEASURED OPERATOR WINDOW (quiet hours are its complement) ════════════════════════════════

@test "10 the window WRAPS midnight: 23:00 and 02:00 are inside, 07:00 is not" {
  CC_SP_HOUR=23 sp cc_sp_in_operator_window
  CC_SP_HOUR=02 sp cc_sp_in_operator_window
  run env CC_SP_HOUR=07 bash -c '. "$1"; cc_sp_in_operator_window' _ "$SP"
  [ "$status" -eq 1 ]
}

@test "11 midnight's 00 does not parse as empty (the octal/strip trap)" {
  CC_SP_HOUR=00 sp cc_sp_in_operator_window
}

@test "12 quiet hours drop the window bonus but never the base reserve" {
  local in out
  in="$(CC_SP_HOUR=12 sp cc_sp_reserve_slots present)"
  out="$(CC_SP_HOUR=07 sp cc_sp_reserve_slots present)"
  [ "$in" -gt "$out" ]
  [ "$out" -gt 0 ]
}

# ══ THE RESERVE ══════════════════════════════════════════════════════════════════════════════════

@test "13 SELF reserves nothing — the reserve never fires on its own beneficiary" {
  [ "$(sp cc_sp_reserve_slots self)" -eq 0 ]
  [ "$(sp cc_sp_reserve_gb self)" -eq 0 ]
}

@test "14 PRESENT reserves strictly more than ABSENT, in both dimensions" {
  [ "$(sp cc_sp_reserve_slots present)" -gt "$(sp cc_sp_reserve_slots absent)" ]
  [ "$(sp cc_sp_reserve_gb present)"    -gt "$(sp cc_sp_reserve_gb absent)" ]
}

@test "15 UNKNOWN reserves exactly what ABSENT does — protection is added on PROVEN presence only" {
  [ "$(sp cc_sp_reserve_slots unknown)" -eq "$(sp cc_sp_reserve_slots absent)" ]
  [ "$(sp cc_sp_reserve_gb unknown)"    -eq "$(sp cc_sp_reserve_gb absent)" ]
}

# ══ THE CENSUS ═══════════════════════════════════════════════════════════════════════════════════

@test "16 the census counts TREES at the COMMAND POSITION across BOTH families" {
  # 3 real trees: one .exe, one .bin, one .bin child of the .exe (must NOT be counted twice), plus a
  # wrapper that merely NAMES a claude binary in its arguments (must NOT be counted at all — the
  # measured 83-vs-60 overcount) and an unrelated process.
  cat > "$BATS_TEST_TMPDIR/ps" <<'EOF'
#!/bin/bash
cat <<'ROWS'
  101     1 /Applications/x/claude-code/bin/claude.exe --model opus
  102     1 /opt/y/node_modules/.bin/claude
  103   101 /opt/y/node_modules/.bin/claude
  104     1 bash /Users/x/.claude/bin/cc-close-attrib /opt/y/node_modules/.bin/claude --flag
  105     1 /usr/bin/vim notes.txt
ROWS
EOF
  chmod +x "$BATS_TEST_TMPDIR/ps"
  run env -u CC_SP_TREES_OVERRIDE PATH="$BATS_TEST_TMPDIR:$PATH" \
    bash -c '. "$1"; cc_sp_trees' _ "$SP"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

@test "17 P1 PARITY — this census and capacity-alarm.sh's agree on ONE ps fixture" {
  # Two copies exist on purpose (see the library header: converting the live 60 s alarm daemon to
  # source this belongs to its own item). A literal diff is not enough — the repo already learned
  # that. This runs BOTH awk programs over the SAME stubbed ps and asserts identical counts, which is
  # the shape that actually broke three times.
  cat > "$BATS_TEST_TMPDIR/ps" <<'EOF'
#!/bin/bash
cat <<'ROWS'
  201     1 /a/claude-code/bin/claude.exe
  202     1 /b/node_modules/.bin/claude
  203   201 /b/node_modules/.bin/claude
  204     1 bash /w/wrapper /b/node_modules/.bin/claude
ROWS
EOF
  chmod +x "$BATS_TEST_TMPDIR/ps"
  mine="$(env -u CC_SP_TREES_OVERRIDE PATH="$BATS_TEST_TMPDIR:$PATH" bash -c '. "$1"; cc_sp_trees' _ "$SP")"
  # capacity-alarm's census() verbatim, extracted by line range so a drift in ITS copy shows up here.
  extract_fn "$REPO/scripts/capacity-alarm.sh" census > "$BATS_TEST_TMPDIR/theirs.sh"
  [ -s "$BATS_TEST_TMPDIR/theirs.sh" ]
  theirs="$(PATH="$BATS_TEST_TMPDIR:$PATH" bash -c '. "$1"; census' _ "$BATS_TEST_TMPDIR/theirs.sh" | awk '{print $1}')"
  [ -n "$mine" ]
  [ -n "$theirs" ]
  [ "$mine" -eq "$theirs" ]
}

@test "18 an unreadable census is a VISIBLE fail-open, never a silent skip" {
  beat s1 999940 999940
  cat > "$BATS_TEST_TMPDIR/ps" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$BATS_TEST_TMPDIR/ps"
  run env -u CC_SP_TREES_OVERRIDE PATH="$BATS_TEST_TMPDIR:$PATH" \
    bash -c '. "$1"; cc_capacity_admit autonomy-x "spawn"; rc=$?; exit $rc' _ "$CA"
  [ "$status" -eq 0 ]
  run jq -r 'select(.caller=="autonomy-x") | .reserve' "$CC_ADMIT_IDL"
  [[ "$output" == *"census UNREADABLE"* ]] || false
}

# ══ THE GATE: the reserve as a refusal ═══════════════════════════════════════════════════════════

@test "19 reserve-slots REFUSES autonomy at the reserved line, and ADMITS it one tree lower" {
  beat s1 999940 999940                       # operator present, and it is not our session
  export CC_ADMIT_SESSION_CEILING=10
  export CC_SP_RESERVE_SLOTS=2 CC_SP_RESERVE_OPERATOR_SLOTS=2 CC_SP_RESERVE_WINDOW_SLOTS=0
  # reserve 4 ⇒ limit 6; trees 6 means 6+1 > 6 ⇒ REFUSE.
  CC_SP_TREES_OVERRIDE=6 run admit autonomy-a "spawn"
  [ "$status" -eq 9 ]
  [[ "$output" == *"reserve"* ]] || false
  # THE CONTROL — one tree lower must ADMIT, or this case is satisfied by a gate that refuses always.
  CC_SP_TREES_OVERRIDE=5 run admit autonomy-b "spawn"
  [ "$status" -eq 0 ]
}

@test "20 DoD — operator PRESENT: the autonomy path is REFUSED while the operator's own fire ADMITS" {
  # ONE pinned world, two gates. This is the wave's definition of done, and it is deliberately a
  # DISAGREEMENT assertion: a gate that refused everything would pass the first half, and one that
  # admitted everything would pass the second.
  beat s1 999940 999940                       # the human drove a turn 60s ago, in another session
  export CC_ADMIT_SESSION_CEILING=10
  export CC_SP_RESERVE_SLOTS=2 CC_SP_RESERVE_OPERATOR_SLOTS=2 CC_SP_RESERVE_WINDOW_SLOTS=0
  export CC_SP_TREES_OVERRIDE=6

  # (a) autonomy — the unattended gate every non-handoff spawn path funnels through.
  run admit autonomy-agent-tool "subagent spawn"
  [ "$status" -eq 9 ]
  [[ "$output" == *"reserve-slots"* ]] || [[ "$output" == *"operator reserve"* ]] || false

  # (b) the operator's own /handoff fire, over the SAME world. capacity_gate() applies no reserve —
  #     the operator IS the reservee — so it must admit. Driven through the real script with only the
  #     capacity gate reachable, using its own CC_FIRE_* seams.
  # capacity_gate() and its bound helpers VERBATIM from the real script — extracted, never
  # re-implemented, or this case would be testing a copy of the gate.
  extract_fn "$REPO/scripts/handoff-fire.sh" \
    _cc_fire_budget_file _cc_fire_budget_reset _cc_fire_presence _cc_fire_bound capacity_gate \
    > "$BATS_TEST_TMPDIR/gate.sh"
  grep -q '^capacity_gate() {' "$BATS_TEST_TMPDIR/gate.sh"
  run env CC_FIRE_LOADAVG_OVERRIDE=1.0 CC_FIRE_HEADROOM_OVERRIDE=64 \
      CC_FIRE_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/fire" \
      bash -c '
        emit_gate_admit()   { :; }
        emit_fire_refusal() { :; }
        CLOUD=0
        . "$1"                                   # the shared terms + the bound
        _CC_KS="$3"
        . "$2"
        capacity_gate' _ "$CA" "$BATS_TEST_TMPDIR/gate.sh" "$REPO/scripts/handoff-fire.sh"
  [ "$status" -eq 0 ]

  # (c) AND THE ASYMMETRY IS NOW BOUNDED IN BOTH DIRECTIONS (§W3 item 2): the operator's gate can no
  #     longer refuse forever. Over a genuinely saturated box it refuses ONCE and then releases.
  run env CC_FIRE_LOADAVG_OVERRIDE=99.0 CC_FIRE_HEADROOM_OVERRIDE=64 \
      CC_FIRE_ADMIT_BUDGET=1 CC_FIRE_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/fire2" \
      bash -c '
        emit_gate_admit()   { :; }
        emit_fire_refusal() { :; }
        CLOUD=0
        . "$1"; _CC_KS="$3"; . "$2"
        capacity_gate; echo "rc1=$?"
        capacity_gate; echo "rc2=$?"' _ "$CA" "$BATS_TEST_TMPDIR/gate.sh" "$REPO/scripts/handoff-fire.sh"
  [[ "$output" == *"rc1=9"* ]] || false
  [[ "$output" == *"rc2=0"* ]] || false
}

@test "21 reserve-headroom REFUSES autonomy over a box the operator's own floor would clear" {
  beat s1 999940 999940
  export CC_ADMIT_MIN_HEADROOM_GB=4
  export CC_SP_RESERVE_GB=0 CC_SP_RESERVE_OPERATOR_GB=4 CC_SP_RESERVE_WINDOW_GB=0
  # 6 GB clears the bare floor of 4 and fails 4+4=8. The row must name reserve-headroom, NOT
  # headroom: one means the box is out, the other means autonomy yielded, and they have different
  # cures.
  CC_ADMIT_HEADROOM_OVERRIDE=6 run admit autonomy-c "spawn"
  [ "$status" -eq 9 ]
  [[ "$output" == *"operator reserve"* ]] || false
  run jq -r 'select(.caller=="autonomy-c") | .term' "$CC_ADMIT_IDL"
  [ "$output" = reserve-headroom ]
  # CONTROL: the same box with the operator ABSENT must admit — the reserve is the only difference.
  rm -f "$CC_BEAT_DIR"/*.json; beat s1 999990 992800
  CC_ADMIT_HEADROOM_OVERRIDE=6 run admit autonomy-d "spawn"
  [ "$status" -eq 0 ]
}

@test "22 SELF is never refused by the reserve — an operator-driven session keeps its fan-out" {
  beat s9 999940 999940
  export CC_ADMIT_SESSION_CEILING=10 CC_SP_TREES_OVERRIDE=8
  export CC_SP_RESERVE_SLOTS=2 CC_SP_RESERVE_OPERATOR_SLOTS=2 CC_SP_RESERVE_WINDOW_SLOTS=0
  # An unattended caller at 8 trees is over the reserved line...
  run admit autonomy-e "spawn"
  [ "$status" -eq 9 ]
  # ...and the SAME world, from the session the operator is driving, admits.
  CC_ADMIT_SID=s9 run admit agent-tool "subagent spawn"
  [ "$status" -eq 0 ]
  run jq -r 'select(.caller=="agent-tool") | .presence' "$CC_ADMIT_IDL"
  [ "$output" = self ]
}

@test "23 the reserve refusal is BOUNDED — it releases and pages, like every other term" {
  beat s1 999940 999940
  export CC_ADMIT_SESSION_CEILING=10 CC_SP_TREES_OVERRIDE=9 CC_ADMIT_BUDGET=2
  run admit autonomy-f "spawn"; [ "$status" -eq 9 ]
  run admit autonomy-f "spawn"; [ "$status" -eq 9 ]
  run admit autonomy-f "spawn"
  [ "$status" -eq 0 ]
  [[ "$output" == *"budget expired"* ]] || false
  [ -s "$BATS_TEST_TMPDIR/pages.txt" ]
}

@test "24 CC_ADMIT_RESERVE_TERM=off leaves the gate exactly as it was, and says so in the row" {
  beat s1 999940 999940
  export CC_ADMIT_SESSION_CEILING=10 CC_SP_TREES_OVERRIDE=9
  CC_ADMIT_RESERVE_TERM=off run admit autonomy-g "spawn"
  [ "$status" -eq 0 ]
  run jq -r 'select(.caller=="autonomy-g") | .presence' "$CC_ADMIT_IDL"
  [ "$output" = term-off ]
}

@test "25 an ABSENT presence library cannot tighten the gate — inertness admits and is recorded" {
  export CC_ADMIT_SESSION_CEILING=10 CC_SP_TREES_OVERRIDE=9
  CC_ADMIT_PRESENCE_LIB=/nonexistent/spawn-presence.sh run admit autonomy-h "spawn"
  [ "$status" -eq 0 ]
  run jq -r 'select(.caller=="autonomy-h") | .presence' "$CC_ADMIT_IDL"
  [ "$output" = unavailable ]
}

@test "26 every row carries presence and reserve, admits included (the §9.5.1 population rule)" {
  beat s1 999940 999940
  run admit autonomy-i "spawn"
  [ "$status" -eq 0 ]
  run jq -r 'select(.caller=="autonomy-i") | [.presence, (.reserve|tostring)] | @tsv' "$CC_ADMIT_IDL"
  [[ "$output" == present* ]] || false
  [[ "$output" == *"slots"* ]] || false
}

@test "27 the ceiling is the MEASURED 54, not the ~15 folklore, and it lives in ONE place" {
  # A ratchet on the number AND on its uniqueness: a second literal anywhere in the two libraries is
  # how a ceiling starts drifting (capacity-admit case 26's lesson, applied to this term).
  run bash -c '. "$1"; printf "%s" "$CC_SP_DEFAULT_CEILING"' _ "$SP"
  [ "$output" -eq 54 ]
  run grep -c 'CC_SP_DEFAULT_CEILING=' "$SP"
  [ "$output" -eq 1 ]
}

@test "28 the presence consult costs one jq pass, not one per beat file" {
  # 400 beat files. A per-file fork here is >15s of PreToolUse latency on the highest-volume spawn
  # surface on the box, i.e. a gate whose own cost exceeds the contention it bounds. The bound is
  # generous (5s) on purpose: this pins the SHAPE (one pass), not a benchmark of the runner.
  local i
  for i in $(seq 1 400); do beat "s$i" 999900 992800; done
  beat live 999940 999940
  local t0 t1
  t0="$(date +%s)"
  [ "$(sp cc_sp_operator_state)" = present ]
  t1="$(date +%s)"
  [ "$(( t1 - t0 ))" -le 5 ]
}

# ══ ONE MUTANT PER SITE — the three cases below RUN ON PRISTINE TRUNK ════════════════════════════
#
# Cases 01-28 mostly go RED on trunk for ONE reason: scripts/lib/spawn-presence.sh does not exist
# there. A missing file fails everything, which is a WEAK red — it credits no individual site and it
# says nothing about the two items whose subjects DO exist on trunk (memory
# per-site-mutation-attributes-coverage). These three are the strong ones: every file they touch is
# present on trunk, so each fails there for the SPECIFIC defect it names and for nothing else.

@test "29 ITEM 2 (runs on trunk) — the operator's gate refuses ONCE, then releases; on trunk it refuses forever" {
  # THE ASYMMETRY, isolated. Nothing here needs the presence library: a saturated box, the operator's
  # own capacity_gate, fired twice. Post-fix: 9 then 0 (bounded — the refusal became an EVENT).
  # On pristine trunk: 9 then 9, and the third, and the hundredth — the unbounded refusal §W3 names as
  # "the ONLY path that can be refused indefinitely is the human's".
  extract_fn "$REPO/scripts/handoff-fire.sh" \
    _cc_fire_budget_file _cc_fire_budget_reset _cc_fire_presence _cc_fire_bound capacity_gate \
    > "$BATS_TEST_TMPDIR/gate.sh"
  grep -q '^capacity_gate() {' "$BATS_TEST_TMPDIR/gate.sh"
  run env CC_FIRE_LOADAVG_OVERRIDE=99.0 CC_FIRE_HEADROOM_OVERRIDE=64 \
      CC_FIRE_ADMIT_BUDGET=1 CC_FIRE_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/fire29" \
      bash -c '
        emit_gate_admit()   { :; }
        emit_fire_refusal() { :; }
        CLOUD=0
        . "$1"; _CC_KS="$3"; . "$2"
        capacity_gate; echo "rc1=$?"
        capacity_gate; echo "rc2=$?"
        capacity_gate; echo "rc3=$?"' _ "$CA" "$BATS_TEST_TMPDIR/gate.sh" "$REPO/scripts/handoff-fire.sh"
  [[ "$output" == *"rc1=9"* ]] || false # the first refusal stands — this is still a real gate
  [[ "$output" == *"rc2=0"* ]] || false # ...and it cannot stand twice
  [[ "$output" == *"rc3=9"* ]] || false # the counter RESET on release, so the gate is not disabled
}

@test "30 ITEM 1 (runs on trunk) — the operator's gate RECORDS what the beat said when it decided" {
  # The consult at THIS spawn site. On trunk capacity_gate reads no beat at all, so its records carry
  # nothing about presence and the DoD claim is uncheckable from the ledger afterwards.
  beat s1 999940 999940
  extract_fn "$REPO/scripts/handoff-fire.sh" \
    _cc_fire_budget_file _cc_fire_budget_reset _cc_fire_presence _cc_fire_bound capacity_gate \
    > "$BATS_TEST_TMPDIR/gate.sh"
  run env CC_FIRE_LOADAVG_OVERRIDE=1.0 CC_FIRE_HEADROOM_OVERRIDE=64 \
      CC_FIRE_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/fire30" \
      bash -c '
        emit_gate_admit()   { printf "ADMIT %s\n" "$*"; }
        emit_fire_refusal() { printf "REFUSE %s\n" "$*"; }
        CLOUD=0
        . "$1"; _CC_KS="$3"; . "$2"
        capacity_gate' _ "$CA" "$BATS_TEST_TMPDIR/gate.sh" "$REPO/scripts/handoff-fire.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"operator present"* ]] || false
}

@test "31 ITEM 3 (runs on trunk) — the Agent tool's hook charges the census and passes its session id" {
  # The highest-volume spawn surface, driven through the REAL hook. On trunk the hook gates on memory
  # headroom ALONE, so a box with 30 GB free admits every subagent regardless of occupancy and of who
  # is at the keyboard — there is no term a session count could refuse.
  beat s1 999940 999940
  export CC_ADMIT_SESSION_CEILING=10 CC_SP_TREES_OVERRIDE=9
  export CC_SP_RESERVE_SLOTS=2 CC_SP_RESERVE_OPERATOR_SLOTS=2 CC_SP_RESERVE_WINDOW_SLOTS=0
  export CC_SPAWN_STATE_DIR="$BATS_TEST_TMPDIR/spawn-budget"
  run bash -c 'jq -n "{session_id:\"s-auto\",cwd:\"/tmp\",tool_input:{prompt:\"do a thing\"}}" \
                 | bash "$1"' _ "$REPO/hooks/agent-teams-enforce.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // "none"')" = deny ]
  printf '%s' "$output" | grep -q "MACHINE CAPACITY"
  # ...and the sid reached the row, which is what makes `self` reachable at all for this caller.
  run jq -r 'select(.caller=="agent-tool") | .sid' "$CC_ADMIT_IDL"
  [ "$output" = s-auto ]
}

# ══ RED-PROOF (recorded — a control that cannot fail proves nothing) ═════════════════════════════
#
# Run against PRISTINE origin/main (the tree BEFORE this wave), reproduce with:
#
#   git worktree add /tmp/w3-pristine origin/main
#   cp tests/spawn-presence.bats /tmp/w3-pristine/tests/
#   cd /tmp/w3-pristine && cc-bats tests/spawn-presence.bats
#
# Expected on pristine trunk: scripts/lib/spawn-presence.sh does not exist, so cases 01-17, 19-22 and
# 24-28 fail on the missing library or on a gate with no reserve term, and case 20(c) fails because
# capacity_gate() has no bound (rc2=9, the unbounded operator refusal this wave removes). The exact
# per-case verdict from the run is recorded in the wave's Status log entry in
# docs/plans/BACKLOG_SELF_DRAINING_2026-08-12.md.
#
# The one case that must be read carefully rather than counted: case 18. On pristine trunk it can
# pass for the WRONG reason — there is no reserve term at all, so a broken census refuses nothing and
# rc 0 is trivially true. What makes it a real case post-fix is the `census UNREADABLE` marker in the
# row, which cannot exist on trunk. Assert the marker, never just the rc.
