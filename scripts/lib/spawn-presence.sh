#!/usr/bin/env bash
# spawn-presence.sh — the SPAWN-SIDE consult of the session presence beat, plus the reserve of local
# capacity that autonomy may never take.
#
# ── WHY THIS FILE EXISTS (measured 2026-08-12, BACKLOG_SELF_DRAINING §W3, backlog 8ae4b508f274) ──
# hooks/lib/cc-beat.sh is the READ side of the presence beat and it is live, cheap and correct. It
# had exactly TWO consumers in the tree — bin/cc-reaper:205-211 and bin/cc-teardown:712-713 — and
# BOTH are teardown-time. Nothing that OPENS a pane asked. So the box knew the operator was at the
# keyboard and every spawner spawned anyway: the single highest-leverage inert guard on the machine.
#
# The consequence the operator actually felt, measured the same day: the load gate is UNBOUNDED
# against the operator's own `/handoff` fire (scripts/handoff-fire.sh capacity_gate), BUDGET-RELEASED
# after N consecutive refusals for unattended callers (scripts/lib/capacity-admit.sh), and was OFF
# entirely for the Agent tool's load term. The ONLY path that could be refused indefinitely was the
# human's. This library is the measurement side of the fix; the policy lives in the two gates.
#
# ══ THE BEAT IS PRESENCE, NEVER A CENSUS ══════════════════════════════════════════════════════════
# MEASURED 2026-08-12T10:45Z on this box, and it is the one thing a reader must not get wrong here:
#
#     beats with t-age <=   60s :    0        ps-derived live session trees : 10
#     beats with t-age <=  300s :    3
#     beats with t-age <=  900s :    6        (of 1,527 beat files on disk)
#
# Zero beats inside a minute while ten sessions were demonstrably alive. That is not a broken
# producer — hooks/session-beat.sh writes at TURN BOUNDARIES (UserPromptSubmit and Stop), so a
# session in the middle of a long turn correctly does not beat, and the ones doing the most work are
# the quietest. The beat is therefore a LOWER BOUND on liveness and a HIGH-CONFIDENCE signal about
# WHO drove a turn. Charging a session ceiling on beat count would read 0 live sessions on a busy box
# and admit everything — the actuator-cannot-see-its-population failure, arriving as a deleted gate.
#
# So the two questions get two instruments, deliberately:
#   PRESENCE  → the beat (cb_operator_age / cb_system_live). Fresh, per-session, attests the human.
#   POPULATION → `ps`, at the COMMAND POSITION, counted as TREES (cc_sp_trees below).
#
# ══ WHAT "UNKNOWN" MAY NOT BECOME ═════════════════════════════════════════════════════════════════
# cc-beat.sh ships an EXISTENCE GATE (cb_system_live) precisely because a beat-less WORLD and a
# beat-less SESSION are different facts with opposite readings. This file keeps that split and adds
# the direction rule for a RESERVE:
#
#   present  the beat system is live AND some session's operatorT is younger than the window
#            ⇒ apply the operator reserve. A PROVEN fact.
#   absent   the system is live and no operator beat is fresh ⇒ base reserve. Also a measurement.
#   unknown  the system is NOT live (producer not deployed, jq missing, dir absent) ⇒ base reserve,
#            recorded under its OWN token. We only ever ADD protection on PROVEN presence: acting on
#            unproven absence is one defect (probe-that-acts-on-absence-must-confirm-presence) and
#            tightening on a dead probe is the other (a producer outage would throttle all autonomy
#            box-wide). One value must never mean both "answered no" and "could not ask"
#            (sensor-default-off-makes-blindness-the-shipping-path), which is why `unknown` is a
#            distinct return string and lands in the gate's row as its own basis.
#
# ── THE OPERATOR WINDOW IS MEASURED, NOT ASSUMED ─────────────────────────────────────────────────
# §W3 item 5 asks for quiet hours on the spawn side. The obvious default — a 09:00-17:00 or
# 08:00-20:00 "working day" — is FALSE for this operator, and the failure mode of guessing is that
# autonomy holds its reserve during the hours the human is asleep and drops it during the hours they
# work. Measured over 978 operator turn-attestations in ~/.claude/cc-beats (local-hour histogram of
# `operatorT`), the tightest contiguous window holding >=90% of them is:
#
#     10:00 -> 04:59 local  (18 h, 90.7% of operator turns)
#     05:00 -> 09:59 local  (5 h,   5.0% — 49 turns; the real trough is early MORNING)
#
# So the default window wraps midnight and the quiet hours are 05:00-09:59. Re-derive rather than
# trust this paragraph — it is a fact about a person and it will drift:
#   for f in ~/.claude/cc-beats/*.json; do jq -r '.operatorT // empty' "$f"; done \
#     | while read -r t; do date -r "$t" +%H; done | sort | uniq -c
#
# ── Caller contract ──────────────────────────────────────────────────────────────────────────────
#   . scripts/lib/spawn-presence.sh
#   cc_sp_ready                        → 0 iff every symbol below is defined (one predicate, like cc_hw_ready)
#   cc_sp_trees                        → live session TREE count on stdout; empty + rc 1 when unreadable
#   cc_sp_active                       → live MID-TURN session count (the ACTIVE population, which is
#                                        what the box binds on — see § THE ACTIVE POPULATION); empty
#                                        + rc 1 when unmeasurable
#   cc_sp_operator_state [sid]         → present | absent | unknown | self   (see above; `self` = the
#                                        SPAWNING session is itself operator-driven, so the spawn is
#                                        the operator spending their own slots — no reserve applies)
#   cc_sp_in_operator_window           → 0 inside the measured window, 1 outside, 2 when the clock is unreadable
#   cc_sp_reserve_slots <state>        → session slots autonomy may not take
#   cc_sp_reserve_gb <state>           → EXTRA reclaimable GB autonomy must leave on top of the floor
#
# Env: CC_SP_OPERATOR_MAX_S(900) · CC_SP_CEILING(54) · CC_SP_RESERVE_SLOTS(2) ·
#      CC_SP_RESERVE_OPERATOR_SLOTS(3) · CC_SP_RESERVE_WINDOW_SLOTS(1) · CC_SP_RESERVE_GB(0) ·
#      CC_SP_RESERVE_OPERATOR_GB(4) · CC_SP_RESERVE_WINDOW_GB(2) ·
#      CC_SP_WINDOW_START(10) · CC_SP_WINDOW_END(5) · CC_SP_NOW · CC_SP_HOUR · CC_SP_TREES_OVERRIDE ·
#      CC_SP_ACTIVE_OVERRIDE · CC_SP_BEAT_LIB
# Pure definitions only — safe to source under `set -u`. bash 3.2-safe, BSD+GNU portable, no eval.

# ══ THE CEILING — the ~15 folklore replaced by the MEASURED floor ══════════════════════════════════
# §W3 item 4: "so '~15 sessions' becomes a real number enforced in ONE place instead of folklore.
# The recon established that ~15 is read by no code today; do not preserve the folklore, replace it
# with the enforced number." This is that one place, and the number is not 15.
#
# 15 was never measured. `scripts/cloud-ceiling-probe.sh:14` and CONCURRENCY_PROGRAM.md:574 both say
# so in as many words ("'~15 concurrent sessions' is folklore precisely because it was never measured
# this way"). What IS measured is scripts/pool-floor.sh's MACHINE FLOOR — the largest session count
# sustained across a run of consecutive capacity-alarm samples with verdict=OK and zero swap growth.
# Run 2026-08-12 against 14,321 samples over 320.7 h:
#
#     {"machine_floor_sessions":54,"machine_floor_run_samples":10,"machine_peak_observed":54,
#      "machine_samples":14321,"machine_healthy_samples":7197,"machine_span_h":320.7}
#
# 54 sustained, all-green, ten consecutive 60 s samples. So the enforced ceiling is 54 and NOT 15:
# a ceiling of 15 would refuse a fleet this box has demonstrably carried, which is the
# fail-closed-degradation-as-amplifier direction and would strand the drain W4 depends on.
#
# A FLOOR USED AS A CEILING IS THE CONSERVATIVE READING, deliberately: pool-floor publishes only
# lower bounds (§S5.2 — the vendor exposes no entitlement, so no upper bound is obtainable), and one
# counter-example sample LOWERS it. Re-derive with `bash scripts/pool-floor.sh --json` rather than
# quoting this comment; a published figure decays with its source
# (memory published-figure-decays-with-its-source).
CC_SP_DEFAULT_CEILING=54

# The measured operator window (see the header). Hours are LOCAL and the window WRAPS midnight, so
# START > END is the normal case here, not an error.
CC_SP_DEFAULT_WINDOW_START=10
CC_SP_DEFAULT_WINDOW_END=5

cc_sp_ready() {
  [ -n "${CC_SP_DEFAULT_CEILING:-}" ] || return 1
  command -v cc_sp_trees              >/dev/null 2>&1 || return 1
  command -v cc_sp_active             >/dev/null 2>&1 || return 1
  command -v cc_sp_operator_state     >/dev/null 2>&1 || return 1
  command -v cc_sp_in_operator_window >/dev/null 2>&1 || return 1
  command -v cc_sp_reserve_slots      >/dev/null 2>&1 || return 1
  command -v cc_sp_reserve_gb         >/dev/null 2>&1 || return 1
  return 0
}

cc_sp_is_int() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; return 0; }

# ── the population: live session TREES, matched at the command position ──────────────────────────
# This awk is the one in scripts/capacity-alarm.sh `census()` (:608-624), and it is here rather than
# re-invented because that function already paid for THREE measured census defects, every one of
# which a fresh implementation re-commits by default:
#   (1) `pgrep -cf` returned 0 against 8 real sessions — macOS pgrep matches a TRUNCATED argv, so a
#       long absolute path never matches. A counter stuck at 0 is a deleted gate. Hence ps.
#   (2) ONE FAMILY IS NOT THE FLEET. Sessions launch under two DISJOINT spellings —
#       `…/claude-code/bin/claude.exe` and `…/node_modules/.bin/claude` — measured intersection ZERO
#       (35 + 25 = 60 trees where the incumbent single pattern saw 35). The fleet is their SUM.
#   (3) MATCHING ANYWHERE IN argv OVERCOUNTS: a whole-line grep read 83 against a true 60, because
#       wrappers such as `bash …/cc-close-attrib …/node_modules/.bin/claude …` merely NAME the
#       binary (memory pgrep-f-matches-agent-briefs). Match the COMMAND POSITION only.
# TREES, not processes: a proc whose parent is in-family is a child of an already-counted tree.
#
# ⚠ TWO COPIES, ONE PINNED BEHAVIOURALLY — and this is stated out loud because the repo has already
# learned that a literal-comparison ratchet is not enough (capacity-admit.sh's own header: a test
# "can DETECT drift; it cannot prevent it, and it says nothing about the nine other lines it never
# compared"). capacity-alarm.sh is a 60 s launchd daemon whose SESSIONS field feeds per-session-MB
# and est_room derivations; converting it to source this library is a real change to a live monitor's
# failure modes and belongs to its own item, NOT to a spawn-side wave (filed alongside this work).
# Until then tests/spawn-presence.bats case P1 runs BOTH implementations against ONE stubbed `ps`
# fixture and asserts identical counts — a behavioural parity control over the shape that actually
# broke three times, not a diff of two literals.
cc_sp_trees() { # → live session tree count | empty + rc 1
  if [ -n "${CC_SP_TREES_OVERRIDE:-}" ]; then
    cc_sp_is_int "$CC_SP_TREES_OVERRIDE" || return 1
    printf '%s' "$CC_SP_TREES_OVERRIDE"; return 0
  fi
  # POSITIVE CONTROL ON THE DENOMINATOR, and it is load-bearing rather than fastidious. Without the
  # `rows` guard this function returns "0" when `ps` produces NOTHING — a dead probe, an exec-deny, a
  # sandbox — because the awk END block prints a well-formed zero over an empty stream. That is the
  # exact defect the header's item (1) is about, arriving from the other side: not a pattern that
  # cannot match, but an instrument that stopped answering, reading back as an EMPTY FLEET and
  # therefore as infinite headroom. A gate charged on it would admit everything, forever, and look
  # healthy (memory positive-control-the-denominator; sensor-default-off-makes-blindness-the-shipping-
  # path). A live box always has processes, so zero input lines is never a measurement of zero
  # sessions — it is the absence of a measurement, and it must reach the caller as rc 1 so the gate
  # can file a VISIBLE fail-open. tests/spawn-presence.bats case 18 pins it; it found this bug.
  local out
  out="$(ps -eo pid=,ppid=,args= 2>/dev/null | awk '
    { rows++
      cmd = $3; f = ""
      if      (cmd ~ /claude-code\/bin\/claude\.exe$/) f = "exe"
      else if (cmd ~ /node_modules\/\.bin\/claude$/)   f = "bin"
      if (f != "") { fam[$1] = f; par[$1] = $2 }
    }
    END {
      if (rows + 0 == 0) exit 1
      n = 0
      for (p in fam) { if (par[p] in fam) continue; n++ }
      printf "%d", n
    }' 2>/dev/null)" || return 1
  cc_sp_is_int "$out" || return 1
  printf '%s' "$out"
}

# ── the beat, resolved the way its two teardown consumers resolve it ─────────────────────────────
# Same source order as bin/cc-reaper and bin/cc-teardown, script-relative FIRST: ~/.claude/hooks/*
# are per-file symlinks into the checkout, so resolving through them reaches the repo's own copy and
# the consult goes live on the trunk fast-forward instead of waiting behind a deploy it cannot
# trigger (the deployed-layer-bootstrap-circle). An EXPLICIT CC_SP_BEAT_LIB is honoured VERBATIM and
# never folded into the fallback list — that is how the absent-beat case is testable at all.
cc_sp_load_beat() { # → 0 when cb_* is available, 1 otherwise. Idempotent.
  command -v cb_operator_age >/dev/null 2>&1 && return 0
  local here d
  here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || here=""
  if [ -n "${CC_SP_BEAT_LIB:-}" ]; then
    if [ -f "$CC_SP_BEAT_LIB" ]; then
      # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
      . "$CC_SP_BEAT_LIB" 2>/dev/null || true
    fi
    command -v cb_operator_age >/dev/null 2>&1 && return 0
    return 1
  fi
  for d in "${here:-.}/../../hooks/lib/cc-beat.sh" \
           "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/cc-beat.sh" \
           "$HOME/.claude/hooks/lib/cc-beat.sh"; do
    if [ -f "$d" ]; then
      # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
      . "$d" 2>/dev/null || true
      command -v cb_operator_age >/dev/null 2>&1 && return 0
    fi
  done
  return 1
}

# ══ THE ACTIVE POPULATION — the second census, and the one the box actually binds on ═══════════════
# (Wave D re-term: backlog 1c45598a91be; DoD docs/research/scaling-bottlenecks-2026-08-09.md §5-P2.)
#
# WHY RESIDENCY IS THE WRONG DENOMINATOR FOR A SPAWN CEILING. cc_sp_trees counts RESIDENT sessions,
# and residency is close to free: axis 01 measured static residency at 0.22% of the segment limit
# with swap 0. What the box binds on is ACTIVITY — a session mid-turn is running work, a resident one
# is mostly not, and at the program's design mix (150 resident / ~10 active) a ceiling charged on
# residency says nothing at all about the other 140 and cannot express the distinction.
#
# NO PER-ACTIVE-SESSION LOAD FIGURE IS QUOTED HERE, DELIBERATELY. This paragraph used to carry "2.5-5
# runnable threads per genuinely ACTIVE session (load1 27.4 -> 44.4 across nine all-active) against
# the 1.6 a MIXED fleet averages to ⇒ ~4-8 concurrent actives". 2.5-5 is an aggregate/N — a ratio,
# not a marginal — and the three other published values are disqualified or underivable; the whole
# adjudication, and the sampler that must supply the replacement, are in
# docs/research/marginal-load-per-active-session-2026-08-19.md (backlog 193ae8ddce72). The ARGUMENT
# above needs no coefficient: it is about which population a ceiling is charged on, not how much one
# member of it costs. Charging it on loadavg instead re-commits the proxy
# §8.5.2 retracted (dominated by the TUI renderer, WindowServer and macOS scanning; §8.5.7 measured
# it swinging 2.05x at CONSTANT session count).
#
# WHAT COUNTS AS ACTIVE, AND WHY IT IS THE BEAT'S `kind`. hooks/session-beat.sh writes at exactly the
# two turn boundaries and labels them: `kind:"prompt"` at UserPromptSubmit, `kind:"stop"` at Stop. A
# session whose LATEST beat is a prompt beat is therefore mid-turn BY CONSTRUCTION — the producer
# already answers this question, it simply had no consumer. The alternative, an instantaneous-CPU
# estimate, is unavailable here on purpose: it needs two samples separated by a sleep, and this
# library's biggest caller is a PreToolUse hook that runs while a tool slot is HELD.
#
# IT IS A PROVEN LOWER BOUND, DELIBERATELY. The header above establishes the beat as a lower bound on
# liveness (a session in a long turn correctly does not beat, and the busiest are the quietest); the
# same applies to this count. That direction is the correct one for a REFUSING term: we tighten only
# on a fact we hold, so an unrecorded turn under-refuses rather than refusing on unproven activity —
# the same law the reserve follows ("only ever ADD protection on PROVEN presence"). A term that
# guessed upward would refuse spawns for a reason nothing on disk could later explain.
#
# LIVENESS IS CHARGED, and it is not fastidiousness: a session that DIES mid-turn leaves its
# `kind:"prompt"` beat on disk forever, so a census that counted beats alone would refuse a little
# more with every crash until the ceiling became unreachable — a gate that tightens monotonically on
# its own accidents. Identity is (pid,lstart), never pid alone (the reaper's S-4 pin and the beat
# writer's own), so a RECYCLED pid cannot inherit a dead session's activity. A beat carrying no
# lstart cannot be proven either way and is NOT counted — same direction rule.
#
# COST: one jq slurp (ONE process over the whole dir, not one per file — the hard requirement stated
# at cc_sp_operator_state) plus at most one `ps`, and the `ps` is skipped entirely when no beat is
# mid-turn. Measured on a 1,527-file fixture: the slurp is ~13 ms.
cc_sp_active() { # → live MID-TURN session count | empty + rc 1 when unmeasurable
  if [ -n "${CC_SP_ACTIVE_OVERRIDE:-}" ]; then
    cc_sp_is_int "$CC_SP_ACTIVE_OVERRIDE" || return 1
    printf '%s' "$CC_SP_ACTIVE_OVERRIDE"; return 0
  fi
  command -v jq >/dev/null 2>&1 || return 1
  cc_sp_load_beat || return 1
  local now live_max dir out line maxt pairs pids pid n
  now="$(cb_now 2>/dev/null)" || now=""
  cc_sp_is_int "$now" || return 1
  live_max="${CC_BEAT_LIVE_MAX_S:-900}"
  cc_sp_is_int "$live_max" || live_max=900
  dir="$(cb_beat_dir)"
  [ -d "$dir" ] || return 1

  # ONE jq pass, emitting the existence-gate clock on the first line and one `P<pid> <lstart>` line
  # per mid-turn beat. A torn or invalid file makes jq exit non-zero over the WHOLE slurp, which
  # lands on rc 1 — never a parsed half-answer, exactly as cc_sp_operator_state treats it.
  out="$(jq -rs '
      (map(select((.t|type) == "number") | .t) | max) as $maxt
      | ["T\($maxt)"]
        + ( map(select(.kind == "prompt" and (.pid|type) == "number"
                       and ((.lstart // "") | tostring | length) > 0))
            | map("P\(.pid) \(.lstart)") )
      | .[]' "$dir"/*.json 2>/dev/null)" || return 1

  maxt=""; pairs=""; pids=""
  while IFS= read -r line; do
    case "$line" in
      T*) maxt="${line#T}" ;;
      P*) line="${line#P}"
          pid="${line%% *}"
          cc_sp_is_int "$pid" || continue
          # Darwin PID_MAX is 99998, and macOS ps does not skip an out-of-range pid — it ABORTS the
          # WHOLE query ("ps: process id too large"), zero rows, so one corrupt beat would blind the
          # census into permanent abstention (the positive control below then rc-1s every call, and
          # the admit gate loses its ACTIVE term fleet-wide). An out-of-range pid cannot name a live
          # session, so it is dead by definition: drop it from the query, never let it poison ps.
          [ "$pid" -le 99998 ] || continue
          pairs="${pairs}${line}
"
          pids="${pids},${pid}" ;;
    esac
  done <<EOF
$out
EOF

  # THE EXISTENCE GATE, cb_system_live's rule verbatim (the same one cc_sp_operator_state applies):
  # with no beat younger than the live window the producer's world is not demonstrably producing, so
  # "0 active" would be manufactured out of a dead sensor rather than measured. Two auditors over one
  # population must share the state model (memory sibling-auditors-must-share-the-state-model).
  cc_sp_is_int "$maxt" || return 1
  if [ "$maxt" -le "$now" ] && [ "$(( now - maxt ))" -gt "$live_max" ]; then return 1; fi

  # No candidate at all is a REAL zero, not a blind one: the existence gate above already proved the
  # producer is live, and there is nothing for `ps` to adjudicate. Skipping the fork here is what
  # keeps the common case (a quiet box) free.
  [ -n "$pids" ] || { printf '0'; return 0; }

  # ONE ps, with a POSITIVE CONTROL ON THE DENOMINATOR. Our own pid rides in the query and must come
  # back: without it a `ps` that exec-denied, sandboxed or stopped answering returns no rows, every
  # candidate reads as dead, and the census reports 0 — the actuator-cannot-see-its-population
  # failure arriving as a deleted gate (memory positive-control-the-denominator). lstart is compared
  # after the SAME normalisation hooks/session-beat.sh applies when it writes the field (squeeze
  # runs of whitespace, trim both ends), so the two strings are comparable by construction.
  #
  # COUNTED AS DISTINCT PIDS, NOT AS BEAT LINES, and this is the same correction cc_sp_trees already
  # carries one function above (it counts TREES, skipping any process whose parent is in-family).
  # Two beats can resolve to ONE claude ancestor — session-beat.sh walks up to the nearest
  # claude/claude.exe process, and subagents share their lead's — so counting rows would report two
  # ACTIVE units for one session tree. It would also be the wrong DIRECTION for this term: the whole
  # census is a proven lower bound, and a duplicate is not evidence of a second concurrent turn.
  n="$(printf '%s\n@@\n%s' "$(ps -o pid=,lstart= -p "$$${pids}" 2>/dev/null)" "$pairs" | awk -v self="$$" '
    function norm(s) { gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
    /^@@$/ { sec = 1; next }
    sec == 0 { p = $1; $1 = ""; live[p] = norm($0); seen[p] = 1; next }
    { p = $1; $1 = ""; if ((p in seen) && live[p] == norm($0)) hit[p] = 1 }
    END { if (!(self in seen)) exit 1; n = 0; for (p in hit) n++; printf "%d", n }' 2>/dev/null)" || return 1
  cc_sp_is_int "$n" || return 1
  printf '%s' "$n"
}

# ── presence ─────────────────────────────────────────────────────────────────────────────────────
# `self` is checked FIRST and it is the reason this takes a sid at all. The Agent tool's PreToolUse
# hook knows the SPAWNING session's id; if the operator drove that session's last turn, the spawn is
# the operator spending their own capacity and the reserve must not apply to it. Without this the
# gate would refuse the human's own fan-out in order to protect the human — the reserve turned
# against its beneficiary (memory guard-refusal-fires-on-its-own-harness).
#
# ── ONE JQ PASS, AND THAT IS A HARD REQUIREMENT, NOT AN OPTIMISATION ─────────────────────────────
# cb_system_live() loops the beat dir and forks jq PER FILE. That is fine where it lives — the reap
# path, once, off the hot path — but this library's biggest caller is a PreToolUse hook on the Agent
# tool, the highest-volume spawn surface on the box, and it runs while a tool slot is HELD.
# Measured 2026-08-12: 1,527 beat files on disk. Per-file jq at ~10 ms is >15 s of hook latency on
# every subagent spawn, i.e. a gate whose own cost is worse than the contention it exists to bound
# (memory bound-must-fit-the-band-not-the-bench). So both facts come from a SINGLE jq invocation over
# the whole directory: max(.t) for the existence gate and max(.operatorT) for presence.
#
# The semantics are cb_system_live's VERBATIM — same `.t` field, same CC_BEAT_LIVE_MAX_S window — and
# that agreement is pinned by tests/spawn-presence.bats case P2, which runs this function and
# cb_system_live over the same fixtures and asserts they never disagree. Two auditors over one
# population must share the state model (memory sibling-auditors-must-share-the-state-model); a
# faster copy that drifts on which files count is a worse instrument than the slow one.
cc_sp_operator_state() { # [sid] → self | present | absent | unknown
  local sid="${1:-}" max age now dir pair maxt maxop live_max
  max="${CC_SP_OPERATOR_MAX_S:-900}"
  cc_sp_is_int "$max" || max=900
  if ! cc_sp_load_beat; then printf 'unknown'; return 0; fi
  command -v jq >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  now="$(cb_now 2>/dev/null)" || now=""
  cc_sp_is_int "$now" || { printf 'unknown'; return 0; }
  live_max="${CC_BEAT_LIVE_MAX_S:-900}"
  cc_sp_is_int "$live_max" || live_max=900
  dir="$(cb_beat_dir)"
  [ -d "$dir" ] || { printf 'unknown'; return 0; }

  # SELF FIRST — one file, one jq, and it is the cheap answer that short-circuits the scan for the
  # commonest gated case (an operator-driven session fanning out).
  if [ -n "$sid" ]; then
    age="$(cb_operator_age "$sid" 2>/dev/null)" || age=""
    if cc_sp_is_int "$age" && [ "$age" -le "$max" ]; then printf 'self'; return 0; fi
  fi

  # `jq -s` over the glob: one process, one read, two maxima. A torn/invalid file makes jq exit
  # non-zero over the WHOLE slurp, which lands on the `unknown` arm below — the same direction
  # cb_last_beat takes for a torn single file (absent, never a parsed half-answer).
  pair="$(jq -rs 'reduce .[] as $b ([0,0];
                    [ (if ($b.t|type)=="number" and $b.t > .[0] then $b.t else .[0] end),
                      (if ($b.operatorT|type)=="number" and $b.operatorT > .[1] then $b.operatorT else .[1] end) ])
                  | "\(.[0]) \(.[1])"' "$dir"/*.json 2>/dev/null)" || pair=""
  maxt="${pair%% *}"; maxop="${pair##* }"
  cc_sp_is_int "$maxt" || { printf 'unknown'; return 0; }
  cc_sp_is_int "$maxop" || { printf 'unknown'; return 0; }

  # THE EXISTENCE GATE (cb_system_live's rule): no beat younger than the live window ⇒ the producer's
  # world is not demonstrably producing, so the only honest answer about a human is `unknown`.
  # Asking about presence inside a dead producer's world manufactures "absent" out of nothing.
  if [ "$maxt" -le "$now" ] && [ "$(( now - maxt ))" -gt "$live_max" ]; then printf 'unknown'; return 0; fi

  # Presence: the sticky operator high-water mark across the fleet. A clock that stepped backwards
  # must not forge a huge age and thereby a false "operator long gone" — clamp to presence, the safe
  # direction, exactly as cb_operator_age clamps at 0.
  [ "$maxop" -gt "$now" ] && { printf 'present'; return 0; }
  [ "$(( now - maxop ))" -le "$max" ] && { printf 'present'; return 0; }
  printf 'absent'
}

# ── the measured operator window (quiet hours are its complement) ────────────────────────────────
cc_sp_in_operator_window() { # → 0 inside · 1 outside · 2 clock unreadable
  local h s e
  h="${CC_SP_HOUR:-}"
  [ -n "$h" ] || h="$(date +%H 2>/dev/null || true)"
  h="${h#0}"; [ -n "$h" ] || h=0                      # 08 -> 8; midnight's "00" -> "" -> 0
  cc_sp_is_int "$h" || return 2
  s="${CC_SP_WINDOW_START:-$CC_SP_DEFAULT_WINDOW_START}"
  e="${CC_SP_WINDOW_END:-$CC_SP_DEFAULT_WINDOW_END}"
  cc_sp_is_int "$s" || s="$CC_SP_DEFAULT_WINDOW_START"
  cc_sp_is_int "$e" || e="$CC_SP_DEFAULT_WINDOW_END"
  if [ "$s" -le "$e" ]; then
    [ "$h" -ge "$s" ] && [ "$h" -lt "$e" ] && return 0
    return 1
  fi
  # WRAPS MIDNIGHT — the measured case here (10 -> 5). Inside means h >= 10 OR h < 5.
  { [ "$h" -ge "$s" ] || [ "$h" -lt "$e" ]; } && return 0
  return 1
}

# ── the reserve ──────────────────────────────────────────────────────────────────────────────────
# Two dimensions, because a count alone would not have bitten on the day this was built: the box was
# at 10 sessions of a measured 54-session floor with 30 GB reclaimable, so a pure count reserve is
# inert exactly when the operator complains. Memory headroom is the dimension the box actually binds
# on, and it is the one §8.5.2's retraction certified as sheddable AND session-attributable — so the
# reserve is expressed there too: autonomy must leave the operator's next session's worth of RAM.
#
# `self` reserves NOTHING: the operator is the reservee, and a spawn they drove is theirs to make.
cc_sp_reserve_slots() { # <state> → integer
  local st="${1:-unknown}" base bonus win
  base="${CC_SP_RESERVE_SLOTS:-2}";            cc_sp_is_int "$base"  || base=2
  bonus="${CC_SP_RESERVE_OPERATOR_SLOTS:-3}";  cc_sp_is_int "$bonus" || bonus=3
  win="${CC_SP_RESERVE_WINDOW_SLOTS:-1}";      cc_sp_is_int "$win"   || win=1
  [ "$st" = self ] && { printf '0'; return 0; }
  [ "$st" = present ] || bonus=0
  cc_sp_in_operator_window || win=0
  printf '%s' "$(( base + bonus + win ))"
}

cc_sp_reserve_gb() { # <state> → integer GB ON TOP of the caller's own floor
  local st="${1:-unknown}" base bonus win
  base="${CC_SP_RESERVE_GB:-0}";              cc_sp_is_int "$base"  || base=0
  bonus="${CC_SP_RESERVE_OPERATOR_GB:-4}";    cc_sp_is_int "$bonus" || bonus=4
  win="${CC_SP_RESERVE_WINDOW_GB:-2}";        cc_sp_is_int "$win"   || win=2
  [ "$st" = self ] && { printf '0'; return 0; }
  [ "$st" = present ] || bonus=0
  cc_sp_in_operator_window || win=0
  printf '%s' "$(( base + bonus + win ))"
}
