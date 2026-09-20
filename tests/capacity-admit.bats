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
  # THE THIRD AMBIENT INPUT, and the two overrides above do not touch it. 450a47c50 added the
  # operator RESERVE, which runs over an otherwise-ADMITTING box and refuses on `cc_sp_trees` — a
  # live `ps -eo` census of session trees — plus the operator's presence. A fixtured $HOME does not
  # absent it: _cc_admit_load_presence resolves spawn-presence.sh RELATIVE TO capacity-admit.sh's
  # own directory first, so this suite loaded the REAL library and charged its verdicts against
  # whatever the desk was doing. Measured 2026-08-13, two-sided: 20/20 ambient, and 17/20 under
  # `CC_SP_TREES_OVERRIDE=999` (cases 13, 14 and P3 flip on the census alone). That is precisely the
  # "every assertion here would flip with the mood of the machine" this file's header says the
  # overrides exist to prevent — the header was written before the term existed and quietly stopped
  # being true. The term is switched OFF rather than pinned because this suite has no reserve case
  # to preserve: pinning the census instead would leave the presence read, which resolves partly off
  # the WALL-CLOCK HOUR, so the suite would still be green at noon and unproven at 05:00.
  export CC_ADMIT_RESERVE_TERM=off
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

idl_first() { # $1=jq path → the FIRST non-null value, SLURPED rather than piped into a head
  # A pipe whose right-hand side exits early SIGPIPEs its producer, and under pipefail the pipeline
  # then reads FALSE ON A MATCH. jq slurps the file itself, so there is no pipeline to break.
  jq -rs "map($1) | map(select(. != null)) | .[0] // \"\"" "$CC_ADMIT_IDL"
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

@test "10 EVERY term off records gate-off, never load-only — a blind eval is not a real one" {
  # WIDENED 2026-08-13 BY WAVE D (backlog 1c45598a91be), and the widening is the point rather than
  # bookkeeping. This case used to turn off the load and headroom terms and assert `gate-off`,
  # because those were ALL the terms. The gate now carries four, so that same world leaves
  # `segments` and `active` in force — and recording a real, refusal-capable evaluation as
  # `gate-off` is the §9.5.1 population defect the case exists to prevent, arriving from the other
  # side. The property is unchanged: `gate-off` means NOTHING was evaluated. Only the list did.
  run bash -c '. "$1"
               CC_ADMIT_LOAD_TERM=off CC_ADMIT_HEADROOM_TERM=off \
               CC_ADMIT_SEGMENT_TERM=off CC_ADMIT_ACTIVE_TERM=off cc_capacity_admit c10 "s"' _ "$LIB"
  [ "$status" -eq 0 ]
  [ "$(idl_field '.basis')" = "gate-off" ]
  # and the row must not claim any term was in force
  [ "$(idl_field '.terms // "none"')" = "none" ]
}

@test "10b the OLD pair off with a Wave D term still on is NOT gate-off" {
  # The control for case 10's widening: without it, turning the two original terms off would read
  # back as "the gate was off" while the segment and active terms were live and able to refuse.
  run bash -c '. "$1"; CC_ADMIT_LOAD_TERM=off CC_ADMIT_HEADROOM_TERM=off cc_capacity_admit c10b "s"' _ "$LIB"
  [ "$status" -eq 0 ]
  [ "$(idl_field '.basis')" != "gate-off" ]
  [ "$(idl_field '.terms')" = "segments,active" ]
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

@test "14 rows stay slurpable when \`what\` carries quotes/newlines (the malformed-line class)" {
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

# ══ THE ADMISSION TOKEN (LIMIT_RECOVER_100P W2, 2026-09-19) ════════════════════════════════════
# ONE net-zero operation, TWO gates, 11-16 s apart, in two processes that cannot see each other:
# the fleet's probe ADMITS, the launcher it typed into the pane's shell re-evaluates and REFUSES,
# and the transplant has already run. Measured 2026-09-19 (U05 §3.3): 5 of 5 recoveries, 4 husks.
# The token carries the probe's decision across that process boundary WITHOUT letting a probe widen
# admission — one-shot, TTL-bounded, uid-checked, sid-enforced, probe-inert.
#
# RED AT 6a6f9a129 (recorded, all five): the library has no cc_capacity_token_mint and no
# _cc_admit_token_redeem, so 15/15b/15d return 9 where 0 is asserted, 15c exits 127 on the
# existence leg, and 15e's second run RELEASES (rc 0) because both runs share one counter file.

mint() { # $1=sid [$2=explicit path] → prints the minted token path
  bash -c '. "$1"; cc_capacity_token_mint "$2" "${3:-}"' _ "$LIB" "$1" "${2:-}"
}

@test "15 a minted token ADMITS once over a refusing box, then is GONE" {
  local tok
  tok="$(mint sid-abc)"
  [ -n "$tok" ] || { echo "mint printed nothing"; false; }
  [ -f "$tok" ]
  # 0600, because the file IS an admission: another uid must not be able to read or forge one.
  [ "$(stat -f '%Lp' "$tok")" = "600" ] || { stat -f '%Sp' "$tok"; false; }
  # the record: sid, uid and the term switches the minting evaluation ran with
  grep -q "sid-abc" "$tok"
  grep -q "$(id -u)" "$tok"
  run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$2" CC_ADMIT_WANT_SID=sid-abc \
               cc_capacity_admit c15 "in-place recycle"' _ "$LIB" "$tok"
  [ "$status" -eq 0 ] || { echo "$output"; cat "$CC_ADMIT_IDL"; false; }
  [ "$(idl_field 'select(.basis=="token")|.verdict')" = "admit" ]
  [[ "$(idl_field 'select(.basis=="token")|.detail')" == *"sid-abc"* ]] || false
  [ ! -f "$tok" ]                                   # ONE-SHOT: unlinked on redemption
  # …and the SECOND call, with the same (now absent) token, gets the real box: load 99 REFUSES.
  run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$2" CC_ADMIT_WANT_SID=sid-abc \
               cc_capacity_admit c15 "in-place recycle"' _ "$LIB" "$tok"
  [ "$status" -eq 9 ]
  [ "$(idl_field 'select(.caller=="c15" and .verdict=="refuse")|.term')" = "load" ]
  # never a SILENT refuse: the row says the token was absent
  [[ "$(idl_field 'select(.caller=="c15" and .verdict=="refuse")|.token')" == *"ABSENT"* ]]
}

@test "15b an EXPIRED token does not admit, is still consumed, and names its age" {
  local tok
  tok="$(mint sid-abc)"
  printf '%s\t%s\t%s\t%s\n' "$(( $(date +%s) - 600 ))" sid-abc "$(id -u)" load > "$tok"
  run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN_TTL_S=60 CC_ADMIT_TOKEN="$2" \
               CC_ADMIT_WANT_SID=sid-abc cc_capacity_admit c15b "s"' _ "$LIB" "$tok"
  [ "$status" -eq 9 ]                               # never a silent admit
  [ ! -f "$tok" ]                                   # consumed even though it was stale
  [[ "$(idl_field 'select(.caller=="c15b")|.token')" == *"EXPIRED"* ]] || false
  # W2FA D5 MOVED THIS ONE ASSERTION, and the move IS the fix. It read `= "load"`, i.e. the gate
  # re-evaluated the box in the pane over a stale token — which is the second gate on one net-zero
  # operation, after the transplant, and is the whole defect. The refusal is now terminal and names
  # the token as the term that refused; 15t is the case that pins the rest of that state.
  [ "$(idl_field 'select(.caller=="c15b")|.term')" = "token" ] \
    || { echo "term: $(idl_field 'select(.caller=="c15b")|.term') — a stale token re-decided in the pane"; false; }
}

@test "15c a PROBE never redeems a token (it would spend the caller's admission)" {
  local tok
  tok="$(mint sid-abc)"
  # The existence leg is what makes this RED pre-fix (exit 127 on a library with no redeem); the
  # inertness leg below is the property. Without the first, this case is green in both arms.
  run bash -c '. "$1"; command -v _cc_admit_token_redeem >/dev/null || exit 127
               CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$2" CC_ADMIT_WANT_SID=sid-abc \
               cc_capacity_probe c15c "s"' _ "$LIB" "$tok"
  [ "$status" -eq 9 ]
  [ -f "$tok" ]                                     # untouched — a probe charges nothing, ever
  [ "$(idl_field 'select(.caller=="c15c")|.basis')" = "probe" ]
}

@test "15d a token for ANOTHER sid is REFUSED, names both, and is NOT consumed" {
  # D3-safety R13. Consuming a foreign token would destroy a sibling recovery's admission — one
  # wiring bug becoming two failures — so the sid check runs BEFORE the unlink.
  local tok
  tok="$(mint sid-other)"
  run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$2" CC_ADMIT_WANT_SID=sid-mine \
               cc_capacity_admit c15d "s"' _ "$LIB" "$tok"
  [ "$status" -eq 9 ]
  [ -f "$tok" ] || { echo "a foreign token was CONSUMED — a sibling recovery just lost its admission"; false; }
  note="$(idl_field 'select(.caller=="c15d")|.token')"
  [[ "$note" == *"sid-other"* ]] || { echo "$note"; false; }
  [[ "$note" == *"sid-mine"* ]]  || { echo "$note"; false; }
}

@test "15e the per-RUN budget key isolates two recoveries' refusal counters" {
  # Measured 2026-09-19 (U05 §3.4): five recoveries shared `lr-fire-resume.refusals`. The only one
  # that got through did so on two EARLIER runs' charges, and its release reset the counter for
  # everyone else. With budget 1, run A's refusal must NOT release run B's spawn.
  run bash -c '. "$1"; CC_ADMIT_BUDGET=1 CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_BUDGET_KEY=runA \
               cc_capacity_admit lr-fire-resume "resume A"' _ "$LIB"
  [ "$status" -eq 9 ]
  run bash -c '. "$1"; CC_ADMIT_BUDGET=1 CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_BUDGET_KEY=runB \
               cc_capacity_admit lr-fire-resume "resume B"' _ "$LIB"
  [ "$status" -eq 9 ] || { echo "run B RELEASED on run A's charge — the counters are shared"; ls "$CC_ADMIT_STATE_DIR"; false; }
  [ -f "$CC_ADMIT_STATE_DIR/lr-fire-resume.runA.refusals" ]
  [ -f "$CC_ADMIT_STATE_DIR/lr-fire-resume.runB.refusals" ]
  # …and run B's OWN second refusal does release: the bound still exists, it is just per-run.
  run bash -c '. "$1"; CC_ADMIT_BUDGET=1 CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_BUDGET_KEY=runB \
               cc_capacity_admit lr-fire-resume "resume B"' _ "$LIB"
  [ "$status" -eq 0 ]
}

@test "15f with NO key the state file is byte-identical to the old path (no caller changes)" {
  # The control for 15e: the keying must be opt-in, or every existing caller silently gets a fresh
  # counter and the bound they have been sharing for a month quietly changes shape.
  run bash -c '. "$1"; CC_ADMIT_BUDGET=3 CC_ADMIT_LOADAVG_OVERRIDE=99 cc_capacity_admit c15f "s"' _ "$LIB"
  [ "$status" -eq 9 ]
  [ -f "$CC_ADMIT_STATE_DIR/c15f.refusals" ]
  [ "$(cat "$CC_ADMIT_STATE_DIR/c15f.refusals")" = "1" ]
}

# ══ W2FA — THE FIVE PROPERTIES AN ADVERSARIAL MUTATION PASS FALSIFIED BY EXECUTION ═════════════
# The token above claims: one-shot · TTL-bounded · uid-checked · sid-enforced · probe-inert, with a
# foreign token refused WITHOUT being consumed. Four of those were false in the tree on 2026-09-19.
# Each case below was RED on the unmodified library and names the measurement that convicted it.

@test "15g D1 ONE-SHOT UNDER CONCURRENCY — a rival inside the read-to-unlink window cannot also admit" {
  # MEASURED: two processes redeeming ONE token with the same CC_ADMIT_WANT_SID on a refusing box
  # (load override 99 on 10 cores) BOTH returned rc 0 in 40 of 40 trials. The record was read with
  # awk and only THEN unlinked, so N concurrent redeemers of one token path all admit — one probe
  # admission granting as many spawns as there are readers, in exactly the regime the wave was built
  # for (five concurrent recoveries that day; handoff-fire's boot arm and its watcher can hold the
  # same launcher, hence the same token path, twice).
  #
  # THE WINDOW IS OPENED DETERMINISTICALLY, NOT RACED. A PATH-shadowed `awk` snapshots the record,
  # runs a RIVAL redemption to completion inside the window, and only then hands the snapshot back —
  # so this case is a fact about the ORDERING, not about how fast the box happens to be. A
  # sleep-and-hope race is a flake in one direction and a vacuous pass in the other.
  local tok rival
  tok="$(mint sid-race)"
  [ -n "$tok" ] || { echo "mint printed nothing"; false; }
  mkdir -p "$BATS_TEST_TMPDIR/awkbin"
  cat > "$BATS_TEST_TMPDIR/awkbin/awk" <<EOF
#!/bin/bash
tok="$tok"; barrier="$BATS_TEST_TMPDIR/rival.done"
for a in "\$@"; do
  [ "\$a" = "\$tok" ] || continue
  [ -e "\$barrier" ] && break
  : > "\$barrier"
  snap="\$(/usr/bin/awk "\$@")"
  CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="\$tok" CC_ADMIT_WANT_SID=sid-race \
    /bin/bash -c '. "\$1"; cc_capacity_admit rival "rival spawn"' _ "$LIB" \
    > "$BATS_TEST_TMPDIR/rival.out" 2>&1
  echo \$? > "$BATS_TEST_TMPDIR/rival.rc"
  printf '%s\n' "\$snap"
  exit 0
done
exec /usr/bin/awk "\$@"
EOF
  chmod +x "$BATS_TEST_TMPDIR/awkbin/awk"
  run env PATH="$BATS_TEST_TMPDIR/awkbin:$PATH" CC_ADMIT_LOADAVG_OVERRIDE=99 \
      CC_ADMIT_TOKEN="$tok" CC_ADMIT_WANT_SID=sid-race \
      bash -c '. "$1"; cc_capacity_admit holder "held spawn"' _ "$LIB"
  # POSITIVE CONTROL: without this the case passes vacuously whenever the stub never fired.
  [ -f "$BATS_TEST_TMPDIR/rival.rc" ] || { echo "the rival never ran — the window was never opened"; false; }
  rival="$(cat "$BATS_TEST_TMPDIR/rival.rc")"
  # EXACTLY ONE of the two may admit. WHICH one is immaterial; two is the defect.
  [ $(( (status == 0 ? 1 : 0) + (rival == 0 ? 1 : 0) )) -eq 1 ] \
    || { echo "holder rc=$status rival rc=$rival — ONE probe admission granted TWO spawns"; cat "$CC_ADMIT_IDL"; false; }
}

@test "15h D2 a MALFORMED TTL cannot make every token immortal — an ERROR exit is not a clean false" {
  # MEASURED: with CC_ADMIT_TOKEN_TTL_S='300s' the expiry test `[ "$age" -gt "$TTL" ]` ERRORS with
  # rc 2 (`[: 300s: integer expected` on stderr) and `if` reads that identically to a clean false —
  # so the gate returned rc 0 and ADMITTED a token 315,360,000 s (10 years) old on a box at
  # 9.90 load/core. The TTL is the only thing bounding the stale-admission window and its guard
  # failed OPEN. The recurring class: docs/lessons/predicate-error-exit-is-indistinguishable-from-false.md
  local tok
  tok="$(mint sid-ttl)"
  printf '%s\t%s\t%s\t%s\n' "$(( $(date +%s) - 315360000 ))" sid-ttl "$(id -u)" load > "$tok"
  run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN_TTL_S=300s CC_ADMIT_TOKEN="$2" \
               CC_ADMIT_WANT_SID=sid-ttl cc_capacity_admit c15h "s"' _ "$LIB" "$tok"
  [ "$status" -ne 0 ] \
    || { echo "a 10-YEAR-OLD token ADMITTED: the TTL comparison errored and \`if\` read it as false"; echo "$output"; false; }
  # …and the row must SAY the TTL was unusable. A refusal for an unrelated reason is not this fix.
  [[ "$(idl_field 'select(.caller=="c15h")|.token')" == *"not an integer"* ]] \
    || { echo "token note: $(idl_field 'select(.caller=="c15h")|.token')"; false; }
  # the shell-level symptom itself: nothing may reach stderr complaining about the operand
  [[ "$output" != *"integer expression expected"* ]] || { echo "$output"; false; }
  [[ "$output" != *"integer expected"* ]] || { echo "$output"; false; }
}

@test "15i D3a a token whose one-shot cannot be enforced NEVER admits — the unwritable directory" {
  # MEASURED on the pre-W2FA library: a token in a chmod-555 directory was redeemed THREE
  # consecutive times, all rc 0, and was still present after each — `rm -f … || true` discarded the
  # one failure that mattered and the IDL rows read basis=token/verdict=admit, indistinguishable
  # from one legitimate redemption. The cure is the rename claim (D1): a directory we cannot mutate
  # is a directory in which one-shot cannot be enforced, so there is no admission to carry.
  local dir tok first second
  dir="$BATS_TEST_TMPDIR/ro"; mkdir -p "$dir"
  tok="$(mint sid-ro "$dir/tok")"
  [ -f "$tok" ] || { echo "mint did not create $dir/tok"; false; }
  chmod 555 "$dir"
  run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$2" CC_ADMIT_WANT_SID=sid-ro \
               cc_capacity_admit c15i "s"' _ "$LIB" "$tok"
  first="$status"
  run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$2" CC_ADMIT_WANT_SID=sid-ro \
               cc_capacity_admit c15i "s"' _ "$LIB" "$tok"
  second="$status"
  chmod 755 "$dir"
  [ "$first" -ne 0 ] || { echo "redemption 1 ADMITTED a token that cannot be consumed"; false; }
  [ "$second" -ne 0 ] || { echo "redemption 2 ADMITTED the SAME token — it is replayable forever"; false; }
  [[ "$(idl_first 'select(.caller=="c15i")|.token')" == *"NOT CLAIMED"* ]] \
    || { echo "row: $(idl_first 'select(.caller=="c15i")|.token')"; false; }
}

@test "15j D3b a SYMLINK is not a token — -f and -O follow it, so the target is never consumed" {
  # MEASURED on the pre-W2FA library: with CC_ADMIT_TOKEN pointing at a symlink to a real record,
  # `-f` and `-O` both followed the link and `rm -f` removed only the LINK, so the target survived
  # and re-linking replayed the admission — three redemptions, all rc 0. A token IS an admission;
  # it must be a regular file this uid owns, never a redirection to one.
  local real link i rc
  real="$BATS_TEST_TMPDIR/real-token"
  mint sid-link "$real" >/dev/null
  link="$BATS_TEST_TMPDIR/link-token"
  for i in 1 2 3; do
    ln -sf "$real" "$link"                          # the replayer owns the link, so re-create it
    run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$2" CC_ADMIT_WANT_SID=sid-link \
                 cc_capacity_admit c15j "s"' _ "$LIB" "$link"
    rc="$status"
    [ "$rc" -ne 0 ] || { echo "redemption $i through a SYMLINK ADMITTED"; false; }
  done
  [ -f "$real" ] || { echo "the link's TARGET was consumed — a sibling's token would be destroyed"; false; }
  [[ "$(idl_first 'select(.caller=="c15j")|.token')" == *"SYMLINK"* ]] \
    || { echo "row: $(idl_first 'select(.caller=="c15j")|.token')"; false; }
}

@test "15k D3c the one-shot's unlink is VERIFIED, not assumed — a no-op rm cannot mint a replay" {
  # `rm -f "$t" 2>/dev/null || true` discards the ONE result that decides whether the token is
  # one-shot. The stub below makes every rm a silent no-op, which is what an unwritable directory,
  # an immutable flag or a full inode table produce — and on the pre-W2FA library the token then
  # survived and the next redemption admitted again, with no row saying so.
  local tok first second
  tok="$(mint sid-rm)"
  mkdir -p "$BATS_TEST_TMPDIR/rmbin"
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/rmbin/rm"
  chmod +x "$BATS_TEST_TMPDIR/rmbin/rm"
  run env PATH="$BATS_TEST_TMPDIR/rmbin:$PATH" CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$tok" \
      CC_ADMIT_WANT_SID=sid-rm bash -c '. "$1"; cc_capacity_admit c15k "s"' _ "$LIB"
  first="$status"
  run env PATH="$BATS_TEST_TMPDIR/rmbin:$PATH" CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$tok" \
      CC_ADMIT_WANT_SID=sid-rm bash -c '. "$1"; cc_capacity_admit c15k "s"' _ "$LIB"
  second="$status"
  [ "$second" -ne 0 ] \
    || { echo "rc1=$first rc2=$second — the token replayed because nothing checked the unlink"; false; }
  # …and the surviving copy is NAMED, not assumed away: a discard that did not happen is a fact.
  [[ "$(idl_first 'select(.caller=="c15k")|.token')" == *"NOT removed"* ]] \
    || { echo "row: $(idl_first 'select(.caller=="c15k")|.token')"; false; }
}

@test "15l D4a a token is NOT redeemed without sid enforcement — an empty CC_ADMIT_WANT_SID" {
  # MEASURED on the pre-W2FA library: a token minted for sid-AAA admitted a completely unrelated
  # caller — rc 0, detail reading "issued for sid-AAA" — because the sid test was
  # `[ -n "$want" ] && [ "$sid" != "$want" ]`, i.e. SKIPPED ENTIRELY when the caller set no sid.
  # "SID-ENFORCED" was a caller CONVENTION, not a library property, and the caller that forgets it
  # is exactly the caller that needed it. Unenforceable ⇒ not redeemed, and NOT consumed: nothing
  # about the file was verified, so destroying it would take a sibling recovery's admission too.
  local tok
  tok="$(mint sid-AAA)"
  run bash -c 'unset CC_ADMIT_WANT_SID; . "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$2" \
               cc_capacity_admit c15l "s"' _ "$LIB" "$tok"
  [ "$status" -ne 0 ] \
    || { echo "a token minted for sid-AAA ADMITTED a caller that named no session at all"; echo "$output"; false; }
  [ -f "$tok" ] || { echo "an unverified token was CONSUMED"; false; }
  [[ "$(idl_first 'select(.caller=="c15l")|.token')" == *"sid enforcement"* ]] \
    || { echo "row: $(idl_first 'select(.caller=="c15l")|.token')"; false; }
}

@test "15m D4b a bare integer in a file is NOT a token — cut -f2 without -s returns the whole line" {
  # MEASURED on the pre-W2FA library: a file containing ONLY `date +%s` redeemed — rc 0, detail
  # "issued for 1789862813", file consumed. `cut -f2` WITHOUT `-s` prints the WHOLE line when the
  # delimiter is absent, so the sid field equalled the timestamp; name that number as the wanted sid
  # and any such file is an admission. The record was never validated as the 4-field TAB record the
  # mint writes, so the shape carried no information at all.
  local f n
  f="$BATS_TEST_TMPDIR/not-a-token"
  n="$(date +%s)"
  printf '%s\n' "$n" > "$f"
  run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$2" CC_ADMIT_WANT_SID="$3" \
               cc_capacity_admit c15m "s"' _ "$LIB" "$f" "$n"
  [ "$status" -ne 0 ] || { echo "a file holding one bare integer was redeemed as an admission"; echo "$output"; false; }
  [ -f "$f" ] || { echo "an unidentified file was DELETED by the gate — point it anywhere and it is removed"; false; }
  [[ "$(idl_first 'select(.caller=="c15m")|.token')" == *"MALFORMED"* ]] \
    || { echo "row: $(idl_first 'select(.caller=="c15m")|.token')"; false; }
}

@test "15n D4c a record minted under ANOTHER uid is refused even when the file is ours" {
  # The `-O` test answers a question about the INODE; the record's own uid field answers one about
  # the MINT. A token copied out of another operator's state dir into ours passes -O and is not
  # ours — so the two checks are complementary, not redundant, and the row names which one fired.
  local tok
  tok="$(mint sid-uid)"
  printf '%s\t%s\t%s\t%s\n' "$(date +%s)" sid-uid 999999 load > "$tok"
  run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$2" CC_ADMIT_WANT_SID=sid-uid \
               cc_capacity_admit c15n "s"' _ "$LIB" "$tok"
  [ "$status" -ne 0 ] || { echo "a record minted by uid 999999 ADMITTED under ours"; false; }
  [ -f "$tok" ] || { echo "a record that is not ours was CONSUMED"; false; }
  [[ "$(idl_first 'select(.caller=="c15n")|.token')" == *"999999"* ]] \
    || { echo "row: $(idl_first 'select(.caller=="c15n")|.token')"; false; }
}

# ══ D5 — THE TTL WAS SMALLER THAN THE WINDOW IT MUST CROSS ════════════════════════════════════
# The token is minted BEFORE the transplant and redeemed only after handoff-fire's composer gate
# (CC_RECYCLE_DRAFT_WAIT, 180 s) plus its shell wait (HF_RECYCLE_SHELL_WAIT_S, 600 s), inside a boot
# window (RCY_BOOT_STALE_S, 180 s); recycle_await_verdict sizes the whole recycle at 1200 s from
# those same four names. A TTL of 300 s is shorter than ONE of those stages, so under exactly the
# loaded conditions that produce limits the token was ALWAYS stale by the time the launcher ran —
# and the fall-through then re-created the two-gate split, in the pane, AFTER the transplant.

@test "15r D5a the TTL is SIZED FROM the stages it crosses, read by name from the same variables" {
  # 900 s is longer than the old 300 s TTL and shorter than the derived window (180+600+180+60).
  local tok
  tok="$(mint sid-ttlwin)"
  printf '%s\t%s\t%s\t%s\n' "$(( $(date +%s) - 900 ))" sid-ttlwin "$(id -u)" load > "$tok"
  run bash -c 'unset CC_ADMIT_TOKEN_TTL_S; . "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$2" \
               CC_ADMIT_WANT_SID=sid-ttlwin cc_capacity_admit c15r "s"' _ "$LIB" "$tok"
  [ "$status" -eq 0 ] \
    || { echo "a 900s-old token expired inside a recycle handoff-fire itself sizes at 1200s"; echo "$output"; false; }
  [ "$(idl_first 'select(.caller=="c15r")|.basis')" = "token" ]
}

@test "15s D5a2 the stage variables are READ as an OVERRIDE — exporting them moves the TTL" {
  # SCOPE CORRECTED (W2FA A3): this case proves the names are READ, and nothing more. It EXPORTS
  # them itself, so it says nothing about production, where none of the four is exported by anything
  # in the tree and the derived value is the sum of the library's own literals (measured under
  # `env -i`: 1020). Read alone it licensed the header's "never re-typed" claim over a fixture that
  # manufactured the environment production lacks. The two cases that DO reach production are 15ac
  # (the env -i value) and coverage 31 (the literals against handoff-fire's own defaults).
  local tok
  tok="$(mint sid-ttlvar)"
  printf '%s\t%s\t%s\t%s\n' "$(( $(date +%s) - 900 ))" sid-ttlvar "$(id -u)" load > "$tok"
  run bash -c 'unset CC_ADMIT_TOKEN_TTL_S; . "$1"
               CC_RECYCLE_DRAFT_WAIT=1 HF_RECYCLE_SHELL_WAIT_S=1 RCY_BOOT_STALE_S=1 \
               CC_ADMIT_TOKEN_TTL_SLACK_S=1 CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$2" \
               CC_ADMIT_WANT_SID=sid-ttlvar cc_capacity_admit c15s "s"' _ "$LIB" "$tok"
  [ "$status" -ne 0 ] || { echo "the TTL ignored the stage variables — it is a re-typed literal"; false; }
  [[ "$(idl_first 'select(.caller=="c15s")|.token')" == *"TTL 4s"* ]] \
    || { echo "row: $(idl_first 'select(.caller=="c15s")|.token')"; false; }
}

@test "15t D5b an unredeemable token is a NAMED TERMINAL STATE, never a fresh in-pane evaluation" {
  # A fresh evaluation in the pane IS the defect: it is the second gate, in the second process,
  # after the transplant. Where the caller declared sid enforcement (CC_ADMIT_WANT_SID non-empty)
  # the gate therefore stops at `token-stale` — no term evaluated, no budget charged, and a page —
  # instead of re-deciding on numbers the driver already decided on.
  local tok
  tok="$(mint sid-term)"
  printf '%s\t%s\t%s\t%s\n' "$(( $(date +%s) - 999999 ))" sid-term "$(id -u)" load > "$tok"
  run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=0.01 CC_ADMIT_TOKEN="$2" CC_ADMIT_WANT_SID=sid-term \
               cc_capacity_admit c15t "s"' _ "$LIB" "$tok"
  # the box is QUIET (0.01/core): a fresh evaluation would ADMIT, which is exactly what must not happen
  [ "$status" -eq 9 ] || { echo "rc=$status — the launcher re-decided in the pane"; echo "$output"; false; }
  [ "$(idl_first 'select(.caller=="c15t")|.basis')" = "token-stale" ] \
    || { echo "basis: $(idl_first 'select(.caller=="c15t")|.basis')"; false; }
  [ "$(idl_first 'select(.caller=="c15t")|.term')" = "token" ]
  # the bound is NOT charged: this refusal is about the caller's own input, not about the box
  [ ! -f "$CC_ADMIT_STATE_DIR/c15t.refusals" ] || { echo "a token refusal spent the box's budget"; false; }
  # …and it is an EVENT, not a standing state
  grep 'could not be redeemed' "$BATS_TEST_TMPDIR/pages.txt" >/dev/null \
    || { echo "no page:"; cat "$BATS_TEST_TMPDIR/pages.txt" 2>/dev/null; false; }
}

@test "15u D5c EQUIVALENCE GUARD — CC_ADMIT_TOKEN_REQUIRED=off restores the fall-through verbatim" {
  # EQUIVALENCE GUARD, labelled: this pins the pre-W2FA behaviour, so it is green in both arms by
  # construction. Its power is over the SWITCH, not over the defect — the mutant it kills is one
  # that ignores the kill switch.
  local tok
  tok="$(mint sid-ks)"
  printf '%s\t%s\t%s\t%s\n' "$(( $(date +%s) - 999999 ))" sid-ks "$(id -u)" load > "$tok"
  run bash -c '. "$1"; CC_ADMIT_TOKEN_REQUIRED=off CC_ADMIT_LOADAVG_OVERRIDE=0.01 CC_ADMIT_TOKEN="$2" \
               CC_ADMIT_WANT_SID=sid-ks cc_capacity_admit c15u "s"' _ "$LIB" "$tok"
  [ "$status" -eq 0 ] || { echo "the kill switch did not restore the fresh evaluation"; echo "$output"; false; }
  [ "$(idl_first 'select(.caller=="c15u")|.basis')" = "measured" ]
  [[ "$(idl_first 'select(.caller=="c15u")|.token')" == *"EXPIRED"* ]] || false
}

@test "15v D5d EQUIVALENCE GUARD — a caller presenting NO token keeps the fall-through untouched" {
  # The terminal state may only reach a caller that PRESENTED a driver's decision. boot-resume.sh,
  # reso-resume-one and the Agent hook set no CC_ADMIT_TOKEN at all, so nothing about their
  # evaluation changes: there is no first gate for a second one to contradict.
  run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=0.01 CC_ADMIT_WANT_SID=sid-none \
               cc_capacity_admit c15v "s"' _ "$LIB"
  [ "$status" -eq 0 ]
  [ "$(idl_first 'select(.caller=="c15v")|.basis')" = "measured" ]
}

# ══ W2FA E1-E3 — THREE GUARDS THE SUITE NEVER TOUCHED ═══════════════════════════════════════════
# Each guard below survived a mutation that DELETED it outright while every suite in the tree
# stayed green. A guard with no test is a comment that happens to execute.
#
# HOW THESE THREE ARE SCORED, stated in the NAME so it cannot be mistaken for something stronger.
# There is no fix here — the guards already exist — so a run on the unmodified tree is GREEN and
# proves nothing about the case's power. The only evidence that a guard-test has any power at all
# is THE DEATH OF ITS MUTANT
# (docs/lessons/green-in-both-arms-is-an-equivalence-guard-not-a-red-proof.md), so each carries the
# verbatim mutant it was scored against and each was executed under it:
#   16   the mint's `case "$sid" in ''|*[!A-Za-z0-9._-]*) return 1` deleted
#        → "a sid holding '../..' MINTED: …/state/tokens/../../pwn.rk1ctCNW"
#   16b  the `[ ! -O "$t" ]` arm forced false
#        → row read "token REFUSED: MALFORMED … this line has 1" instead of the ownership verdict
#   16c  `case "$key" in *[!A-Za-z0-9._-]*) key="" ;;` deleted
#        → "the budget counter was written OUTSIDE CC_ADMIT_STATE_DIR: …/escape.refusals"
#
# 16b's RESIDUAL, declared rather than hidden: its mutant dies on the DIAGNOSIS and the ORDERING,
# not on the verdict. Deleting `-O` still refuses, because the record's uid FIELD is checked one
# step later (case 15n) and /etc/hosts is not a 4-field record either way. The verdict-level
# consequence of `-O` needs a file this uid does not own that IS a well-formed token for our sid,
# and creating one requires root — unreachable from a test. What 16b therefore pins is that the
# INODE question is asked, and asked BEFORE the record is parsed, which is the property a refactor
# trusting the uid field would silently drop.

@test "16 E1 MUTANT-SCORED — a hostile sid cannot shape the token FILENAME" {
  # cc_capacity_token_mint composes the path as `mktemp "$dir/$sid.XXXXXXXX"`, so the sid IS a path
  # fragment. The only thing standing between a caller-supplied sid and the filesystem is
  # `case "$sid" in ''|*[!A-Za-z0-9._-]*) return 1`, and nothing pinned it: deleting that line left
  # the suite green. `../..` from the tokens dir lands in $BATS_TEST_TMPDIR, which EXISTS — an
  # escape that resolves nowhere would pass in both arms and prove nothing.
  local out
  mkdir -p "$CC_ADMIT_STATE_DIR/tokens"
  run bash -c '. "$1"; cc_capacity_token_mint "$2"' _ "$LIB" '../../pwn'
  [ "$status" -ne 0 ] || { echo "a sid holding '../..' MINTED: $output"; false; }
  [ -z "$output" ] || { echo "the mint printed a path for a rejected sid: $output"; false; }
  # the escape itself, by glob rather than by find: BSD find does not walk a symlinked start dir
  # without -H, and $BATS_TEST_TMPDIR is one on this box — its null would read as absence.
  set -- "$BATS_TEST_TMPDIR"/pwn.*
  [ ! -e "$1" ] || { echo "the mint wrote OUTSIDE the tokens dir: $1"; false; }
  # the other half of the same guard: an empty sid is a token nothing can be bound to
  run bash -c '. "$1"; cc_capacity_token_mint ""' _ "$LIB"
  [ "$status" -ne 0 ] || { echo "an EMPTY sid minted a token: $output"; false; }
  # …and the guard is not a blanket refusal: the legitimate shape still mints.
  out="$(mint sid-ok.1_2-3)"
  [ -f "$out" ] || { echo "a well-formed sid was refused — the guard is over-wide"; false; }
}

@test "16b E2 MUTANT-SCORED — the -O check asks the INODE question, before the record is parsed" {
  # The "uid-checked (-O)" claim had no test at all. 15n covers the record's own uid FIELD, which is
  # a different question: a token copied out of another operator's state dir passes -O and fails the
  # field, and a file we merely point at fails -O and never reaches the field. Both arms are needed.
  #
  # A file this uid does not own cannot be created without root, so the subject is a root-owned
  # system file and every precondition is ASSERTED rather than assumed — an environment that
  # falsifies the premise must SKIP, not go red about code that is fine
  # (docs/lessons/environment-falsifiable-precondition-must-skip.md).
  local t=/etc/hosts
  [ -f "$t" ] || skip "no root-owned regular file available to test -O against"
  [ ! -L "$t" ] || skip "$t is a symlink on this box — the -L arm fires first, not the -O one"
  [ ! -O "$t" ] || skip "this process OWNS $t — the precondition for the -O arm does not hold here"
  run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$2" CC_ADMIT_WANT_SID=sid-own \
               cc_capacity_admit cE2 "s"' _ "$LIB" "$t"
  [ "$status" -eq 9 ] || { echo "rc=$status over a file this uid does not own"; echo "$output"; false; }
  [[ "$(idl_first 'select(.caller=="cE2")|.token')" == *"not owned by uid"* ]] \
    || { echo "row: $(idl_first 'select(.caller=="cE2")|.token')"; false; }
  # AND it is not consumed. Without this, CC_ADMIT_TOKEN is a remove-anything primitive: point it at
  # any path and the gate unlinks it.
  [ -f "$t" ] || { echo "the gate DELETED a file it does not own"; false; }
}

@test "16c E3 MUTANT-SCORED — a hostile CC_ADMIT_BUDGET_KEY cannot escape the state dir" {
  # `case "$key" in *[!A-Za-z0-9._-]*) key="" ;;` in _cc_admit_state_file is the ONLY thing stopping
  # a run id from steering the refusal counter out of CC_ADMIT_STATE_DIR, and it was untested.
  #
  # THE ESCAPE NEEDS AN EXISTING DIRECTORY, so this case makes one. The path is composed as
  # `$dir/$caller.$key.refusals`, i.e. the first component is always `<caller>.<something>` — a bare
  # `../..` key resolves through a directory that does not exist, the write fails, and the case then
  # passes in BOTH arms over a decorative absence. `x/../../escape` against caller cE3 resolves
  # through the real `<state>/cE3.x/` and lands one level ABOVE the state dir.
  mkdir -p "$CC_ADMIT_STATE_DIR/cE3.x"
  run bash -c '. "$1"; CC_ADMIT_BUDGET=3 CC_ADMIT_LOADAVG_OVERRIDE=99 \
               CC_ADMIT_BUDGET_KEY="x/../../escape" cc_capacity_admit cE3 "s"' _ "$LIB"
  [ "$status" -eq 9 ] || { echo "rc=$status — the refusal never happened, so nothing was counted"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/escape.refusals" ] \
    || { echo "the budget counter was written OUTSIDE CC_ADMIT_STATE_DIR: $BATS_TEST_TMPDIR/escape.refusals"; false; }
  # …and it DEGRADES to the caller-only file rather than to no file at all. An untrackable bound is
  # an UNBOUNDED gate (_cc_admit_spend's own comment), which is the failure a sanitizer must never
  # manufacture out of a bad key.
  [ -f "$CC_ADMIT_STATE_DIR/cE3.refusals" ] \
    || { echo "the key was dropped AND the bound was lost"; ls -R "$CC_ADMIT_STATE_DIR"; false; }
}

# ══ W2FA A2 — AN INTEGER'S CHARSET IS NOT ITS RANGE ════════════════════════════════════════════
# D2 hardened the TTL RESOLVER: `[ "$age" -gt "${CC_ADMIT_TOKEN_TTL_S:-300}" ]` became a resolved
# integer, because `[` does not return false on a non-integer, it ERRORS rc 2 and `if` reads that
# as a clean false. The fix validated the CHARSET only, so the identical fail-open survived one
# layer in — and the derived TTL added two more readings of the same characters. All four cases
# below were RED on the parent commit and each carries its measured red.

@test "15w A2a an IN-CHARSET but OUT-OF-RANGE TTL cannot make a token immortal either" {
  # MEASURED on the parent: CC_ADMIT_TOKEN_TTL_S=999999999999999999999 is all digits, so the D2
  # resolver accepted it verbatim; bash then printed `[: 999999999999999999999: integer expected`
  # and the gate returned rc 0 over a 10-YEAR-OLD token on a box at 9.90 load/core. Identical
  # symptom to 15h, one validator further in.
  local tok
  tok="$(mint sid-range)"
  printf '%s\t%s\t%s\t%s\n' "$(( $(date +%s) - 315360000 ))" sid-range "$(id -u)" load > "$tok"
  run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN_TTL_S=999999999999999999999 \
               CC_ADMIT_TOKEN="$2" CC_ADMIT_WANT_SID=sid-range cc_capacity_admit c15w "s"' _ "$LIB" "$tok"
  [ "$status" -ne 0 ] \
    || { echo "a 10-YEAR-OLD token ADMITTED on a 21-digit TTL — the comparison errored and \`if\` read it as false"; echo "$output"; false; }
  [[ "$(idl_first 'select(.caller=="c15w")|.token')" == *"not an integer"* ]] \
    || { echo "row: $(idl_first 'select(.caller=="c15w")|.token')"; false; }
  # the shell-level symptom itself — nothing may reach stderr complaining about the operand
  [[ "$output" != *"integer expression expected"* ]] || { echo "$output"; false; }
  [[ "$output" != *"integer expected"* ]] || { echo "$output"; false; }
}

@test "15x A2b an out-of-range STAGE cannot wrap the derived TTL — including to a NEGATIVE bound" {
  # The derived default is `$(( draft + shell + boot + slack ))`, and `$(( ))` wraps silently at
  # int64. MEASURED on the parent: CC_RECYCLE_DRAFT_WAIT=99999999999999999999 → TTL
  # 7766279631452242759 (a token nothing can ever expire) and CC_RECYCLE_DRAFT_WAIT=int64-max →
  # TTL -9223372036854774969 (every token instantly expired). One unvalidated operand, both
  # failure directions — so this case asserts the VALUE, not merely a verdict.
  run bash -c 'unset CC_ADMIT_TOKEN_TTL_S; . "$1"
               CC_RECYCLE_DRAFT_WAIT=9223372036854775807 _cc_admit_token_ttl
               printf "%s" "$CC_ADMIT_TOKEN_TTL_VALUE"' _ "$LIB"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" -gt 0 ] || { echo "the derived TTL is $output — a NEGATIVE bound expires every token"; false; }
  [ "$output" = 1020 ] || { echo "the out-of-range stage was not rejected: TTL=$output (expected the 180 fallback ⇒ 1020)"; false; }
  run bash -c 'unset CC_ADMIT_TOKEN_TTL_S; . "$1"
               CC_RECYCLE_DRAFT_WAIT=99999999999999999999 _cc_admit_token_ttl
               printf "%s" "$CC_ADMIT_TOKEN_TTL_VALUE"' _ "$LIB"
  [ "$output" = 1020 ] || { echo "a 20-digit stage wrapped the TTL to $output"; false; }
}

@test "15y A2c a LEADING ZERO is decimal, not octal — and never aborts the arithmetic" {
  # `$(( 0600 ))` is OCTAL 384. MEASURED on the parent: CC_RECYCLE_DRAFT_WAIT=0600 gave TTL 1224
  # instead of 1440 — silently 216 s short, in the direction that expires tokens mid-recycle — and
  # CC_RECYCLE_DRAFT_WAIT=0900 is not a valid octal literal at all, so bash aborted with
  # `0900: value too great for base` and, under `set -e`, took the whole process with it. The
  # second arm is run under `set -e` BECAUSE lr-fire-resume sources this library that way.
  run bash -c 'unset CC_ADMIT_TOKEN_TTL_S; . "$1"
               CC_RECYCLE_DRAFT_WAIT=0600 _cc_admit_token_ttl
               printf "%s" "$CC_ADMIT_TOKEN_TTL_VALUE"' _ "$LIB"
  [ "$output" = 1440 ] || { echo "0600 was read as octal 384: TTL=$output (expected 600+600+180+60=1440)"; false; }
  run bash -c 'set -e; unset CC_ADMIT_TOKEN_TTL_S; . "$1"
               CC_RECYCLE_DRAFT_WAIT=0900 _cc_admit_token_ttl
               printf "%s" "$CC_ADMIT_TOKEN_TTL_VALUE"' _ "$LIB"
  [ "$status" -eq 0 ] \
    || { echo "the arithmetic aborted under set -e — a caller that sources this library DIES: $output"; false; }
  [ "$output" = 1740 ] || { echo "0900 did not resolve to decimal 900: TTL=$output"; false; }
  [[ "$output" != *"value too great for base"* ]] || { echo "$output"; false; }
}

@test "15z A2d the RECORD'S OWN issued field is the other operand, and is bounded the same way" {
  # `age=$(( now - issued ))` has TWO operands and D2 hardened neither. The record's epoch field is
  # attacker- and corruption-reachable, all-digits, and feeds a subtraction that wraps at int64.
  #
  # MEASURED on the parent, verdict-level: with issued = 2^64 + now - 5 — twenty digits, every one
  # a digit, so cc_hw_is_int passes it — the subtraction wraps to an age of 5 SECONDS and the gate
  # returned rc 0 on a box at 9.90 load/core. A token dated 584 years into the future admitted as
  # if it had been minted five seconds ago.
  command -v python3 >/dev/null 2>&1 || skip "python3 is needed to compose an operand past int64"
  local tok issued
  issued="$(python3 -c 'import time;print(18446744073709551616 + int(time.time()) - 5)')"
  [ "${#issued}" -eq 20 ] || { echo "the wrap operand is ${#issued} digits, not 20 — the premise moved"; false; }
  tok="$(mint sid-issued)"
  printf '%s\t%s\t%s\t%s\n' "$issued" sid-issued "$(id -u)" load > "$tok"
  run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$2" \
               CC_ADMIT_WANT_SID=sid-issued cc_capacity_admit c15z "s"' _ "$LIB" "$tok"
  [ "$status" -ne 0 ] \
    || { echo "a token dated 2^64 s in the future ADMITTED — the age subtraction wrapped to 5s"; echo "$output"; false; }
  [[ "$(idl_first 'select(.caller=="c15z")|.token')" == *"epoch integer"* ]] \
    || { echo "row: $(idl_first 'select(.caller=="c15z")|.token')"; false; }
  # …and the SAME field one digit shorter must not merely produce a nonsense diagnosis either: on
  # the parent a 20-digit epoch wrapped NEGATIVE and the row read "EXPIRED (-7766279629662303726s
  # old)", which refuses for a reason that is arithmetically meaningless.
  tok="$(mint sid-issued2)"
  printf '%s\t%s\t%s\t%s\n' 99999999999999999999 sid-issued2 "$(id -u)" load > "$tok"
  run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$2" \
               CC_ADMIT_WANT_SID=sid-issued2 cc_capacity_admit c15z2 "s"' _ "$LIB" "$tok"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$(idl_first 'select(.caller=="c15z2")|.token')" != *"-"*"s old"* ]] \
    || { echo "the row reports a NEGATIVE age: $(idl_first 'select(.caller=="c15z2")|.token')"; false; }
}

# ══ W2FA A1 — THE TERMINAL STATE REPEATS, AND IT PAGED EVERY TIME ══════════════════════════════
# D5 made an unredeemable token a NAMED TERMINAL STATE that pages instead of re-deciding in the
# pane, and 15t pins that. What neither pinned is that the state can REPEAT: the rename claim is
# the only terminal path that leaves the record on disk (post-claim, clock and expiry all discard
# it first), so an unclaimable token reaches the same refusal for as long as anyone runs the
# launcher — and the launcher is durable in the run's bundle precisely so a human can re-run it
# hours later. MEASURED on the parent: ten redemptions, ten rc-9 refusals, TEN BYTE-IDENTICAL
# PAGES, on a box a fresh evaluation would have ADMITTED.

@test "15aa A1 the terminal refusal is BOUNDED — ten of them are ONE page, and repeat 2..10 say so" {
  local dir tok i rcs="" pages rows
  dir="$BATS_TEST_TMPDIR/a1"; mkdir -p "$dir"
  tok="$(mint sid-a1 "$dir/tok")"
  [ -f "$tok" ] || { echo "mint did not create $dir/tok"; false; }
  chmod 555 "$dir"                                  # neither the claim rename nor an unlink can land
  for i in 1 2 3 4 5 6 7 8 9 10; do
    # the REASON is what the operator reads, so it is captured rather than the rc alone — the
    # gate's rc stays the subshell's (this is the admit() helper's contract, inlined because the
    # helper cannot carry CC_ADMIT_TOKEN).
    run bash -c '. "$1"; CC_ADMIT_LOADAVG_OVERRIDE=0.01 CC_ADMIT_TOKEN="$2" CC_ADMIT_WANT_SID=sid-a1 \
                 cc_capacity_admit cA1 "in-place recycle"; rc=$?; cc_capacity_admit_reason; exit $rc' _ "$LIB" "$tok"
    rcs="$rcs$status "
  done
  chmod 755 "$dir"
  # THE VERDICT IS UNTOUCHED. Bounding an ALARM must never widen ADMISSION — the box here is QUIET
  # (0.01/core), so a fall-through would admit, and that is the failure the terminal state exists
  # to prevent. Ten refusals, still ten refusals.
  [ "$rcs" = "9 9 9 9 9 9 9 9 9 9 " ] || { echo "verdicts changed: $rcs"; false; }
  # …and the record is genuinely still there, which is what makes the repeat possible at all.
  [ -f "$tok" ] || { echo "the token WAS consumed — this case is no longer testing a repeat"; false; }
  pages="$(wc -l < "$BATS_TEST_TMPDIR/pages.txt" | tr -d ' ')"
  [ "$pages" = 1 ] || { echo "$pages pages for one standing state — the alarm is unbounded"; cat "$BATS_TEST_TMPDIR/pages.txt"; false; }
  # THE ROWS ARE NOT DAMPED, only the page is: the IDL is the audit surface and every occurrence
  # must be selectable there. Damping the record instead would hide the storm rather than bound it.
  rows="$(idl_field 'select(.basis=="token-stale" and .caller=="cA1")|.detail' | wc -l | tr -d ' ')"
  [ "$rows" = 10 ] || { echo "$rows rows for 10 refusals — the record was damped, not the alarm"; false; }
  [[ "$(idl_field 'select(.caller=="cA1")|.detail' | head -1)" == *"occurrence 1"* ]] \
    || { echo "first row: $(idl_field 'select(.caller=="cA1")|.detail' | head -1)"; false; }
  [[ "$(idl_field 'select(.caller=="cA1")|.detail' | tail -1)" == *"occurrence 10"* ]] \
    || { echo "tenth row: $(idl_field 'select(.caller=="cA1")|.detail' | tail -1)"; false; }
  # THE REPEAT IS DISTINGUISHABLE IN THE OPERATOR-FACING SENTENCE TOO, not only on the row: the
  # advice for occurrence 1 ("re-fire") and for occurrence 10 ("re-running cannot help") differ.
  [[ "$output" == *"REPEAT #10"* ]] || { echo "the tenth refusal reads identically to the first: $output"; false; }
}

@test "15ab A1b the page bound is a KNOB, and 0 silences the alarm without touching the refusal" {
  # Without this the bound is a constant nobody can move: an operator watching a known-bad recovery
  # must be able to silence the alarm, and a noisier tier must be reachable, WITHOUT either of them
  # reaching the verdict. Both arms assert rc 9 for that reason.
  local dir tok i rcs=""
  dir="$BATS_TEST_TMPDIR/a1b"; mkdir -p "$dir"
  tok="$(mint sid-a1b "$dir/tok")"
  chmod 555 "$dir"
  for i in 1 2 3 4 5; do
    run bash -c '. "$1"; CC_ADMIT_TOKEN_TERMINAL_PAGES=3 CC_ADMIT_LOADAVG_OVERRIDE=0.01 \
                 CC_ADMIT_TOKEN="$2" CC_ADMIT_WANT_SID=sid-a1b cc_capacity_admit cA1b "s"' _ "$LIB" "$tok"
    rcs="$rcs$status "
  done
  chmod 755 "$dir"
  [ "$rcs" = "9 9 9 9 9 " ] || { echo "the knob reached the verdict: $rcs"; false; }
  [ "$(wc -l < "$BATS_TEST_TMPDIR/pages.txt" | tr -d ' ')" = 3 ] \
    || { echo "PAGES=3 produced $(wc -l < "$BATS_TEST_TMPDIR/pages.txt") pages"; cat "$BATS_TEST_TMPDIR/pages.txt"; false; }
  : > "$BATS_TEST_TMPDIR/pages.txt"
  dir="$BATS_TEST_TMPDIR/a1c"; mkdir -p "$dir"
  tok="$(mint sid-a1c "$dir/tok")"
  chmod 555 "$dir"
  run bash -c '. "$1"; CC_ADMIT_TOKEN_TERMINAL_PAGES=0 CC_ADMIT_LOADAVG_OVERRIDE=0.01 \
               CC_ADMIT_TOKEN="$2" CC_ADMIT_WANT_SID=sid-a1c cc_capacity_admit cA1c "s"' _ "$LIB" "$tok"
  chmod 755 "$dir"
  [ "$status" -eq 9 ] || { echo "silencing the alarm changed the verdict to $status"; false; }
  [ ! -s "$BATS_TEST_TMPDIR/pages.txt" ] || { echo "PAGES=0 still paged:"; cat "$BATS_TEST_TMPDIR/pages.txt"; false; }
  # …and the refusal is still RECORDED. A silenced alarm must never become a silent refusal.
  [ "$(idl_first 'select(.caller=="cA1c")|.basis')" = "token-stale" ] \
    || { echo "basis: $(idl_first 'select(.caller=="cA1c")|.basis')"; false; }
}

@test "15ac A3 EQUIVALENCE GUARD, MUTANT-SCORED — under env -i the TTL is the LITERAL sum" {
  # The header claimed the TTL was "read by name, never re-typed" from handoff-fire's constants.
  # MEASURED: none of the four names is exported by anything in the tree, so under `env -i` every
  # read misses and the value is this file's own literals. That is not a defect — it is the honest
  # production value — but it must be PINNED, because the claim that it tracks handoff-fire is what
  # made nobody check. This case is half the tripwire; coverage case 31 is the other half.
  #
  # env -i, not `unset`: a bats process carries the operator's whole environment, so unsetting the
  # four names proves nothing about a fifth arriving from somewhere. env -i is the floor.
  #
  # GREEN IN BOTH ARMS BY CONSTRUCTION — the A3 fix changed a CLAIM, not a value, so a run on the
  # parent passes too and proves nothing on its own. Its only evidence of power is the death of its
  # mutant (docs/lessons/green-in-both-arms-is-an-equivalence-guard-not-a-red-proof.md), scored
  # verbatim: the slack literal 60 → 120 in _cc_admit_token_ttl
  #   → "the production TTL is 1080, not the documented 1020 — a literal moved without its pin".
  run env -i /bin/bash -c '. "$1"; _cc_admit_token_ttl; printf "%s" "$CC_ADMIT_TOKEN_TTL_VALUE"' _ "$LIB"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = 1020 ] \
    || { echo "the production TTL is $output, not the documented 1020 — a literal moved without its pin"; false; }
  # TWO-SIDED, which is what makes the size non-arbitrary rather than merely bigger. The lower bound
  # is the stages it must cross (180+600 = 780); the upper is handoff-fire's whole-recycle bound.
  [ "$output" -ge 780 ] || { echo "TTL $output cannot survive its own operation (780s of stages)"; false; }
  [ "$output" -le 1200 ] || { echo "TTL $output outlives the recycle that minted it (1200s)"; false; }
}
