#!/usr/bin/env bash
# capacity-admit.sh — the BOUNDED machine-capacity admission term for the spawn paths that
# `handoff-fire.sh`'s `capacity_gate()` does not reach.
#
# ── WHY THIS EXISTS, AND WHY IT IS NOT `capacity_gate()` ───────────────────────────────────────
# MACHINE_CAPACITY_V2 §12.1 measured the coverage of the one hardware term in the tree: it guards
# `lr-reset-poller.sh` / `lr-handoff.sh` (both route through handoff-fire) and NOTHING ELSE. Four
# spawn paths bypass it — `boot-resume.sh`, `limit-recover/lr-fire-resume.sh`,
# `~/.reso/bin/reso-resume-one`, and the **`Agent` tool**, which is the highest-volume spawn
# surface on the box. handoff-fire's own header claims *"EVERY fire mode funnels through this
# script"*; §12.1 records that sentence as false in the tree.
#
# The obvious fix — bind `capacity_gate()` to all of them — is REFUTED, twice, and this file must
# not quietly re-commit it:
#
#   §8.5.2 retraction  discard "1-min loadavg/ncpu as the saturation proxy with a fixed 2.0 ceiling
#                      and NO SUSTAINED-SATURATION ESCAPE".
#   §12.2 live proof   2026-07-31 12:13, load 21.55 on 10 cores = 2.16/core — already over the
#                      ceiling — with 13 sessions, 24 GB free and 0 B compressor. A perfectly
#                      healthy box. The existing gate bound to all seven paths refuses EVERY spawn
#                      at that moment, including every recovery path, and §8.5.7 shows it cannot
#                      recover: iTerm2 + WindowServer + XProtect are ~2.4 UNSHEDDABLE cores, so
#                      refusing spawns cannot lower the number the gate reads.
#                      (`fail-closed-degradation-as-amplifier`; memory
#                      `universalizing-a-mechanism-promotes-its-latent-leak`.)
#
# So the defect §12.2 names is not the TERM — it is the UNBOUNDEDNESS. That is exactly the law the
# deploy lane's adversarial reply narrowed §3 to on 2026-08-07
# (docs/research/inertness-generator-2026-08-07.md §9, accepted):
#
#     > No gate on an actuation path may be unbounded. Every affirmative-permission predicate must
#     > carry a finite budget whose expiry converts the standing state into an EVENT — advance+page,
#     > escalate, or revert.
#
# This library is that shape and `capacity_gate()` is not: **a refusal here is bounded by
# construction.** After CC_ADMIT_BUDGET consecutive refusals the next evaluation ADMITS with
# `basis:"budget-expired"` and PAGES. A saturated box can therefore delay a spawn, and can never
# stand as a permanent refusal on a recovery path — which is precisely the outage §12.2 measured.
# The counter resets on any admit, so the bound is on CONSECUTIVE refusals, not lifetime ones.
#
# It is also the answer to §12.4's latent bomb: `boot-resume.sh` resumes at GUI login, i.e. into the
# boot storm (MEASURED loadavg 346 at boot+2 min, decaying to 89 within 90 s). A gate there must
# shed — and must not be able to convert "the box crashed" into "the box never recovers".
#
# ── WHY ITS OWN CC_ADMIT_* NAMESPACE (this is deliberate, not drift) ───────────────────────────
# handoff-fire.sh already reasoned this out for `CC_FIRE_SYSCTL` vs capacity-alarm's `CC_CAP_SYSCTL`:
# sharing one variable between two subjects lets a stub aimed at ONE silently redirect the OTHER.
# Same rule here. What IS pinned across the two implementations is the pair of DEFAULTS (2.0/core,
# 4 GB) and the `basis` vocabulary — and as of 2026-08-07 the defaults are no longer PINNED at all,
# they are SHARED: `capacity_gate()` expands the same `CC_HW_DEFAULT_*` constants defined below, so
# there is one literal to change and nothing left to drift. tests/capacity-admit-coverage.bats cases
# 26/26b/26c are now a ratchet on that structure rather than a comparison between two copies.
# (The header used to name `tests/capacity-admit-parity.bats`, which has never existed in the tree —
# memory `spec-named-mechanism-may-be-prose-only`. The real assertions were always in the coverage
# suite; the name is corrected here rather than left to be re-discovered.)
#
# ── THE basis VOCABULARY IS SHARED ON PURPOSE ──────────────────────────────────────────────────
# `measured` · `load-only` · `fail-open` · `gate-off` are capacity_gate()'s own (§9.5.1);
# `headroom-only` and `budget-expired` are this file's additions, both of which exist because a
# caller here may run ONE term (see CC_ADMIT_LOAD_TERM) or be released by the bound. `absent` is the
# seventh and is the only one NO gate can emit for itself: it means the library was unreachable, so
# it is written by the CALLER (hooks/agent-teams-enforce.sh, and capacity_gate() since the terms
# moved here) to keep an ungated spawn out of the admitted-and-measured population. §9.5.1's rule
# applies verbatim to all seven and is the whole reason
# the field exists: this gate FAILS OPEN on an unreadable sysctl/vm_stat, so a dead probe otherwise
# manufactures a 100%-admit population indistinguishable from a quiet box — the gate deleted,
# reading as the gate healthy. SPLIT ON `basis` AND `blind` BEFORE BELIEVING ANY RATIO COMPUTED FROM
# THESE ROWS — `blind` is Wave D's addition and the amendment is explained at the terminal admit in
# cc_capacity_admit: with four terms, one dead probe may no longer fail-open the three healthy ones,
# so "could not read" became a PER-TERM state that `basis` alone can no longer express.
#
# ── Caller contract ────────────────────────────────────────────────────────────────────────────
#   . scripts/lib/capacity-admit.sh
#   cc_capacity_admit <caller> [what]     → 0 = ADMIT, 9 = REFUSE
#       FOUR TERMS as of Wave D (backlog 1c45598a91be), each independently switchable, each naming
#       itself in the row's `term` field on a refusal:
#         load       loadavg per core            — off on the Agent-tool path (see below)
#         headroom   reclaimable GB              — the term that fired 0 times in 127 refusals
#         segments   compressor-segment %        — the memory term that CAN bind (§S6.6 item 2)
#         active     sessions mid-turn           — the ~8 ceiling the design point rests on (item 1)
#       plus the operator reserve's three: reserve-headroom · reserve-active · reserve-slots.
#       <caller>  short stable id, [A-Za-z0-9._-] only. Keys the budget state file, so two callers
#                 cannot spend each other's budget. An unusable id fails OPEN (recorded) rather
#                 than refusing — a gate must not be able to convict on its own bad wiring.
#       [what]    free text naming the spawn, carried into the record and the page.
#   cc_capacity_admit_reason               → the human sentence for the last evaluation.
#
# Every return path emits ONE record. There is no silent branch, and no `return 0` may acquire one:
# tests/capacity-admit.bats greps this function for exactly that property (the same standing test
# capacity_gate() carries), so a term added later with a bare `return 0` goes RED.
#
# Env: CC_ADMIT_GATE(on) · CC_ADMIT_MAX_LOAD_PER_CORE(2.0) · CC_ADMIT_MIN_HEADROOM_GB(4) ·
#      CC_ADMIT_MAX_SEGMENT_PCT(50) · CC_ADMIT_ACTIVE_CEILING(8) · CC_ADMIT_ACTIVE_RESERVE(1) ·
#      CC_ADMIT_BUDGET(3) · CC_ADMIT_SYSCTL · CC_ADMIT_LOADAVG_OVERRIDE · CC_ADMIT_HEADROOM_OVERRIDE ·
#      CC_ADMIT_SEGMENT_OVERRIDE · CC_SP_ACTIVE_OVERRIDE ·
#      CC_ADMIT_STATE_DIR · CC_ADMIT_IDL · CC_ADMIT_NOTIFY_BIN ·
#      CC_ADMIT_LOAD_TERM(on) · CC_ADMIT_HEADROOM_TERM(on) · CC_ADMIT_SEGMENT_TERM(on) ·
#      CC_ADMIT_ACTIVE_TERM(on)  — per-caller term selection
# Pure definitions only — safe to source under `set -u`. bash 3.2-safe, BSD+GNU portable, no eval.

# ══ THE HARDWARE TERMS — ONE IMPLEMENTATION, TWO POLICIES ══════════════════════════════════════
# Everything from here to `CC_ADMIT_REASON` is the MEASUREMENT, and it is shared verbatim with
# `capacity_gate()` in scripts/handoff-fire.sh. Until 2026-08-07 the two gates each carried their
# own copy of all of it — the same sysctl resolver, the same load/core awk, the same 10-line vm_stat
# parser, and their own literal 2.0 and 4 — and the only thing holding them together was a test that
# compared the two literals. A test can DETECT drift; it cannot prevent it, and it says nothing
# about the nine other lines it never compared (a page-size fix landed on one side and not the other
# would have been invisible to it). One implementation removes the class.
#
# WHAT IS DELIBERATELY *NOT* SHARED — this is an extraction, never a unification:
#   · the POLICY. `capacity_gate()` is UNBOUNDED by design (a human is at the keyboard to read the
#     refusal and act on it, and `--recycle` is exempt at its call site because a replacement fire is
#     net-zero panes). `cc_capacity_admit()` is BUDGET-BOUNDED because its callers are unattended
#     (boot storm, limit-recovery, the Agent tool), where a standing refusal becomes the outage
#     §12.2 measured. Both are correct FOR THEIR CALLERS; folding them into one gate would
#     re-commit the refuted fix (`universalizing-a-mechanism-promotes-its-latent-leak`).
#   · the ENV NAMESPACES. CC_FIRE_* vs CC_ADMIT_* stay separate for the stub-redirection reason
#     given above. Only the DEFAULT VALUES below are shared, and each gate expands them itself.
#   · the RECORDERS. capacity_gate writes handoffs.jsonl through its own emit_gate_admit /
#     emit_fire_refusal; this file writes the IDL. A library that reaches into its caller's
#     telemetry is the defect this file's `_cc_admit_emit` header already refuses to commit.
#   · scripts/capacity-alarm.sh. It reads the same vm_stat, and it is NOT a third copy of this: it
#     is a different INSTRUMENT — a monitor with warn/alarm rungs at 1.5/2.5 per core that also sums
#     the compressor, active and wired populations these gates deliberately exclude. Sharing a
#     parser between a gate and an alarm would make one subject's tuning the other's regression.
#
# Function namespace is `cc_hw_*`, distinct from `cc_capacity_admit` (the bounded gate above it) and
# from capacity-alarm's `CC_CAP_*` env prefix, so a grep for any one of the three cannot pick up the
# other two.

# The ONE literal for each term. Both gates expand these; neither may carry a number of its own
# (tests/capacity-admit-coverage.bats case 26 is the ratchet). 4 GB is M10's reclaimable floor.
#
# 🚨 2.0/core IS NOT DERIVED, and the citation that used to stand here made it look like it was.
# This line read *"2.0/core is §9.5's measured ceiling"* until 2026-08-24. MACHINE_CAPACITY_V2 §9.5
# is titled "SELF-CORRECTION — my 'permanent dispatch outage' projection is FALSIFIED"; it derives
# no ceiling. It observes the gate refusing at 2.92-5.98/core and admitting at 1.55, i.e. that a
# threshold thresholds — and those same refusing readings are the SURVIVED population that proves
# no threshold on this axis can work. The citation pointed at the evidence AGAINST the number.
# The real origin is 0fc3a3d33 (2026-07-29), whose body measures the motivating lag incident at
# 2.72/core and then states "default 2.0" with no rule connecting the two — below the incident it
# was chosen from, and below every load this box has been recorded surviving.
#
# DERIVED 2026-08-24 (item e981656df348) — docs/research/load-ceiling-derivation-2026-08-24.md:
#   · the axis admits NO capacity constant, twice over. Catching the one fatal reading (2.53/core,
#     the 08-05 panic) needs T <= 2.53; not firing on the survived population needs T > 5.98
#     (13 consecutive samples at a CONSTANT 31-32 sessions, plus reso's 42 h at 2.50 and §12.2's
#     healthy 2.16). Disjoint intervals — the repo's own [[threshold-must-separate-fatal-from-
#     survived]], already written into capacity-alarm's rung 7 and never applied here. At the
#     shipped 2.0 the term scores specificity 0.00 over 20 survived readings.
#   · a capacity model needs a stable ambient; ambient moved 8.35 -> 46.39 in ONE day and is 87.3%
#     of the numerator, so this one literal expresses "50 sessions" and "0 sessions" on the same
#     box on the same day.
#   · the blocked marginal is now measured: one ADDITIONAL working session is ~1.16% of the box's
#     runnable population (~0.23 load units at the 20.0 ceiling), ~0.22% when resident at a prompt.
#     The decision variable is ~0.6% of the noise in the quantity being thresholded.
#   · under the ONLY admissible rule — a runaway circuit-breaker above the whole survived
#     population — the derived value is 8.0/core, which is what .claude/commands/ship.md:118
#     already derived from this same population for the land gate on 2026-08-08. Two gates on one
#     box differ 4x on one axis for no derived reason.
# THE NUMBER IS DELIBERATELY UNCHANGED HERE. Moving it is a gate default on the universal spawn
# chokepoint and belongs with the term decision the doc sequences (§6: finish #170's demotion on
# boot-resume-launch.sh:266 / lr-fire-resume.sh:318, XOR set the breaker to 8.0 — never both).
# What still evaluates this literal at all: only those two unattended recovery callers. The fire
# path has had CC_FIRE_LOAD_TERM off since 2026-08-21 (task #170) and the Agent-tool path
# CC_ADMIT_LOAD_TERM=off since Wave D.
CC_HW_DEFAULT_MAX_LOAD_PER_CORE=2.0
CC_HW_DEFAULT_MIN_HEADROOM_GB=4

# `cc_hw_ready` — 0 only when this library is fully present. A caller that sources it defensively
# (handoff-fire.sh must: it is the universal spawn chokepoint, and an undefined function there would
# make `capacity_gate || exit 9` refuse EVERY fire on a missing file — fail-CLOSED, the §12.2
# amplifier exactly) tests this ONE predicate instead of guessing at individual symbols.
cc_hw_ready() {
  [ -n "${CC_HW_DEFAULT_MAX_LOAD_PER_CORE:-}" ] || return 1
  [ -n "${CC_HW_DEFAULT_MIN_HEADROOM_GB:-}" ]   || return 1
  command -v cc_hw_load_verdict     >/dev/null 2>&1 || return 1
  command -v cc_hw_headroom_gb      >/dev/null 2>&1 || return 1
  command -v cc_hw_headroom_verdict >/dev/null 2>&1 || return 1
  command -v cc_hw_resolve_sysctl   >/dev/null 2>&1 || return 1
  command -v cc_hw_budget_charge    >/dev/null 2>&1 || return 1
  command -v cc_hw_compressor_segment_pct >/dev/null 2>&1 || return 1
  command -v cc_hw_segment_verdict        >/dev/null 2>&1 || return 1
  return 0
}

# ── the probes ─────────────────────────────────────────────────────────────────────────────────
# RESOLVED ABSOLUTELY. `sysctl` is in /usr/sbin, which a launchd PATH lacks — measured, not feared:
# of 239 capacity rows written over 2026-08-03..06, 222 read `hw.ncpu unreadable ('')` because the
# bare name never resolved (item 02ae8ae886a1; fix 81871d23 was the same bug in capacity-alarm).
# An EXPLICIT override is honoured VERBATIM and only the DEFAULT falls back — folding the override
# into the fallback list is how an override stops being one
# (memory `path-resolved-dependency-in-daemon-code`).
cc_hw_resolve_sysctl() { # $1=explicit override, may be empty → the binary to run
  if [ -n "${1:-}" ]; then printf '%s' "$1"; return 0; fi
  if [ -x /usr/sbin/sysctl ]; then printf '%s' /usr/sbin/sysctl; else printf '%s' sysctl; fi
}

# Both reads swallow their own failure: an unreadable probe must reach the caller as an EMPTY
# STRING it can file as `fail-open`, never as a non-zero status that errexit turns into a refusal.
# A MISSING ARGUMENT takes the same exit, and that is not fastidiousness: a bare `$1` under the
# `set -u` its callers run is an unbound-variable HARD ERROR, which in a `$( )` assignment is a
# non-zero status — i.e. a mis-call of a probe would become a refusal in the universal spawn
# chokepoint. Every failure this file can have must point the same way, including its own.
cc_hw_ncpu()  { [ -n "${1:-}" ] || return 0; "$1" -n hw.ncpu 2>/dev/null || true; }
cc_hw_load1() { [ -n "${1:-}" ] || return 0; "$1" -n vm.loadavg 2>/dev/null | awk '{print $2}' || true; }

# vm_stat stays on its BARE NAME on purpose and this is a measurement, not an oversight: it lives in
# /usr/bin, the floor of every PATH including a launchd one, so it is reachable where sysctl is not.
# tests/handoff-fire-capacity-gate.bats P7 pins that asymmetry so the claim is checked, not recalled.
#
# Sums exactly free+speculative+inactive+purgeable — what a new session can take WITHOUT swapping.
# `Pages active`/`Pages wired down` are not reclaimable and `Pages purged` is a LIFETIME COUNTER,
# not a population; summing any of them overstates headroom by hundreds of GB. The page size comes
# from vm_stat's OWN header rather than a hardcoded 4096, which would understate an Apple-silicon
# box 4x and refuse every fire (tests 17/18 are that pair).
cc_hw_headroom_gb() { # → reclaimable GB to 2dp on stdout; rc 1 + no output when unreadable
  local vms
  vms="$(vm_stat 2>/dev/null || true)"
  printf '%s\n' "$vms" | awk '
    function n(s,   t) { t = s; gsub(/[^0-9]/, "", t); return t + 0 }
    /page size of/        { ps = n($0) }
    /^Pages free:/        { p += n($0); k++ }
    /^Pages speculative:/ { p += n($0); k++ }
    /^Pages inactive:/    { p += n($0); k++ }
    /^Pages purgeable:/   { p += n($0); k++ }
    END { if (ps <= 0 || k < 4) exit 1; printf "%.2f", p * ps / 1073741824 }
  ' 2>/dev/null || return 1
  return 0
}

# ── THE COMPRESSOR-SEGMENT TERM — the memory term that can actually BIND ───────────────────────
# (Wave D re-term: backlog 1c45598a91be; DoD docs/research/scaling-bottlenecks-2026-08-09.md §5-P2,
# specified by CONCURRENCY_PROGRAM.md §S6.6 item 2.)
#
# WHY THE HEADROOM TERM ABOVE IS NOT ENOUGH, MEASURED RATHER THAN ARGUED. `free + speculative +
# inactive + purgeable >= 4 GB` has fired **0 times in 127 refusals** and *cannot* bind: it counts
# dirty-anonymous inactive pages as free. Side by side on the quiet box the gate term read 40.55 GB
# (ADMIT) while the segment term read 0.00%; AT THE PANIC the gate term read 29.79 GB — still ADMIT —
# against segments at 100%. Every existing rung read a HEALTHY box at death while the kernel's own
# memorystatus verdict already said `"compressor_exhausted": 1`.
#
# THE ARITHMETIC IS NOT INVENTED HERE. It is §7.7's cheap-sysctl recipe, which
# scripts/compressor-sentinel.sh has computed every 10 s since 2026-08-05:
#     in-core segments  = vm_stat "Pages occupied by compressor" / (segment_buffer / pagesize)
#     swapped segments  = vm.swapusage used-bytes / segment_buffer   (EXACT — swap is allocated in
#                         one-segment compressed chunks)
#     pct               = 100 * (in-core + swapped) / vm.compressor_segment_limit
# Swapped-out segments are INCLUDED on purpose and it is not double-counting: a swapped segment still
# holds its descriptor against the limit, which is precisely the ceiling the 2026-07-30 panic hit
# ("100% of segments limit") while only 33% of the compressed-PAGES limit was in use. The divisor is
# DERIVED, never the literal 4 — four is right only at a 16 KiB page size, and a 4 KiB box needs 16.
# `zprint`, the one instrument that reads the descriptor count directly, HANGS under the very storm
# it measures and is banned from any hot path, this one included.
#
# ⚠️ WHAT THIS TERM IS NOT: a panic guard. §4a is explicit — the kernel's own edge signal fires at 98%
# of the limit, which at the measured ramp is SEVEN POINT SIX SECONDS of warning, so "any actuator
# keyed on the ceiling is too late by construction". That job belongs to the sentinel, which keys on
# level AND RATE and can act. A single-sample gate has no rate term and must not pretend to: what
# THIS term does is refuse to ADD a session's demand to a box already deep in a burst — the
# sheddable, session-attributable direction §8.5.2's retraction asked for. The two are complements,
# which is also why the headroom term stays: a steady-state session compresses nothing, so segments
# alone would be blind to plain residency exhaustion.
#
# THIS IS A THIRD READER of vm_stat in the tree and that is deliberate, on the same rule the header
# gives for scripts/capacity-alarm.sh: a gate, a monitor and a daemon are different INSTRUMENTS, and
# sharing a parser would make one subject's tuning another's regression. What must not drift is the
# ARITHMETIC, so tests/capacity-admit-active.bats runs THIS implementation and the sentinel's own
# segs_in_core/segs_swapped over one fixture and asserts they agree — a behavioural control over the
# shape that actually breaks, not a diff of two literals.
cc_hw_swap_used_bytes() { # stdin: a vm.swapusage line → used bytes | rc 1
  # The unit suffix is PARSED, never assumed to be M: a silent 1024x misread here would understate
  # the half of the pool that lives on disk (compressor-sentinel.sh's parse_swap_used_bytes, same
  # arithmetic, same reason).
  awk '
    { for (i = 1; i < NF; i++) if ($i == "used") { v = $(i + 2); break } }
    END {
      if (v == "") exit 1
      u = substr(v, length(v)); n = substr(v, 1, length(v) - 1) + 0
      m = (u == "G") ? 1073741824 : (u == "M") ? 1048576 : (u == "K") ? 1024 : 0
      if (m == 0) exit 1
      printf "%.0f", n * m
    }' 2>/dev/null
}

cc_hw_compressor_segment_pct() { # $1=sysctl binary → "<pct> <segs> <limit>" | rc 1 + no output
  local sb="${1:-}" lim buf swap_raw swap_b row pgsz pages
  [ -n "$sb" ] || return 1
  lim="$("$sb" -n vm.compressor_segment_limit 2>/dev/null)" || return 1
  cc_hw_is_int "$lim" || return 1
  [ "$lim" -gt 0 ] || return 1
  buf="$("$sb" -n vm.compressor_segment_buffer_size 2>/dev/null)" || return 1
  cc_hw_is_int "$buf" || return 1
  [ "$buf" -gt 0 ] || return 1
  # EVERY input is required. An absent one returns rc 1 so the caller can file a VISIBLE blind term:
  # "could not measure" must never render as the healthy value — the exact defect capacity-alarm.sh
  # ate on its launchd PATH, and the reason the sentinel SKIPS a tick rather than emitting a 0.
  swap_raw="$("$sb" -n vm.swapusage 2>/dev/null)" || return 1
  [ -n "$swap_raw" ] || return 1
  swap_b="$(printf '%s\n' "$swap_raw" | cc_hw_swap_used_bytes)" || return 1
  cc_hw_is_num "$swap_b" || return 1
  # Page size from vm_stat's OWN header, never a hardcoded 4096 (16384 on Apple silicon; assuming
  # 4096 understates 4x — the same trap cc_hw_headroom_gb documents two functions above).
  row="$(vm_stat 2>/dev/null | awk '
    NR == 1 { if (match($0, /page size of [0-9]+/)) {
                s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); pg = s + 0 } }
    /^Pages occupied by compressor:/ { c = $NF + 0; gsub(/[^0-9]/, "", c); seen = 1 }
    END { if (pg > 0 && seen) printf "%d %d", pg, c }' 2>/dev/null)" || return 1
  [ -n "$row" ] || return 1
  pgsz="${row%% *}"; pages="${row##* }"
  cc_hw_is_int "$pgsz" || return 1
  cc_hw_is_int "$pages" || return 1
  awk -v p="$pages" -v pg="$pgsz" -v buf="$buf" -v s="$swap_b" -v lim="$lim" 'BEGIN {
    if (buf < pg) exit 1
    segs = int(p / (buf / pg)) + int(s / buf)
    printf "%.2f %d %d", 100 * segs / lim, segs, lim
  }' 2>/dev/null || return 1
  return 0
}

# ── the verdicts ───────────────────────────────────────────────────────────────────────────────
# All three are pure awk over already-validated numbers, so they cannot fail and cannot record: WHAT
# to do with a REFUSE is the policy each gate owns (refuse unboundedly, or spend a unit of budget).
cc_hw_load_verdict() { # $1=load $2=ncpu $3=ceiling → "REFUSE 2.72" | "ADMIT 0.10"
  awk -v l="$1" -v n="$2" -v c="$3" \
    'BEGIN { lpc = l / n; printf "%s %.2f", (lpc > c ? "REFUSE" : "ADMIT"), lpc }'
}
cc_hw_headroom_verdict() { # $1=reclaimable GB $2=floor GB → REFUSE | ADMIT
  awk -v h="$1" -v f="$2" 'BEGIN { print (h < f ? "REFUSE" : "ADMIT") }'
}
cc_hw_segment_verdict() { # $1=segment pct in use $2=ceiling pct → REFUSE | ADMIT
  awk -v s="$1" -v c="$2" 'BEGIN { print (s > c ? "REFUSE" : "ADMIT") }'
}

# ── the validators ─────────────────────────────────────────────────────────────────────────────
# Every caller fails OPEN on a false here — a gate must never convict on its own unreadable input.
cc_hw_is_int() { case "${1:-}" in ''|*[!0-9]*)  return 1 ;; esac; return 0; }
cc_hw_is_num() { case "${1:-}" in ''|*[!0-9.]*) return 1 ;; esac; return 0; }

# ── THE BOUND, SHARED (2026-08-12, §W3 item 2) ─────────────────────────────────────────────────
# Until now the bound was this file's alone, and that asymmetry WAS the defect §W3 exists to remove:
# `capacity_gate()` in scripts/handoff-fire.sh — the OPERATOR's own `/handoff` path — was the only
# unbounded affirmative-permission gate on an actuation path in the tree, while every UNATTENDED
# caller here was budget-released after N consecutive refusals. So on a box whose loadavg sits over
# the ceiling for structural reasons (§12.2: 2.16/core with 13 sessions, 24 GB free, 0 B compressor —
# iTerm2 + WindowServer + XProtect are ~2.4 UNSHEDDABLE cores), the human's fire could be refused
# forever and autonomy's could not. The gate protecting the box was outbidding its owner.
#
# WHICH WAY THE ASYMMETRY WAS RESOLVED, and why it is this way round: the operator's path GAINS the
# release; autonomy does NOT lose its own. Removing autonomy's release would re-commit precisely the
# architecture §8.5.2's retraction and §12.2's live measurement refuted — a permanent refusal on an
# unattended recovery path is an outage, not a safeguard, and it cannot self-clear because refusing
# spawns does not lower the number the gate reads. Whereas §9's narrowed law ("no gate on an
# actuation path may be unbounded") was never satisfied by capacity_gate() at all. One law, applied
# to both, with each gate keeping its OWN budget size and its own records — see cc_hw_budget_charge's
# callers: the operator's is deliberately SMALLER (default 1) because a human is present to read the
# refusal and shed, so one refusal is the whole message and a second is just an obstacle.
#
# PURE MECHANISM, NO POLICY: this returns WHICH SIDE of the bound the caller is on and writes only
# the counter. What to say, what to record and whom to page stays with each gate — a library that
# reached into its caller's telemetry is the defect _cc_admit_emit's header already refuses.
#   rc 0  = charged; the caller may still REFUSE (budget remains)
#   rc 10 = RELEASED; the budget is spent and reset — the caller must ADMIT and page
#   rc 1  = the bound is UNTRACKABLE (no state file, bad budget) — the caller must ADMIT, because an
#           untracked bound is an unbounded gate, and it must never convict on its own bad wiring.
cc_hw_budget_charge() { # $1=state-file (may be empty) $2=budget → 0 charged / 10 released / 1 untrackable
  local sf="${1:-}" budget="${2:-}" n
  [ -n "$sf" ] || return 1
  cc_hw_is_int "$budget" || return 1
  n="$(cat "$sf" 2>/dev/null || echo 0)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  n=$((n + 1))
  if [ "$n" -gt "$budget" ]; then
    : > "$sf" 2>/dev/null || true
    return 10
  fi
  printf '%s\n' "$n" > "$sf" 2>/dev/null || true
  CC_HW_BUDGET_N="$n"
  return 0
}
CC_HW_BUDGET_N=0
# ══ END OF THE SHARED TERMS ════════════════════════════════════════════════════════════════════

# Last-evaluation sentence, for a caller that wants to print or page it.
CC_ADMIT_REASON=""
cc_capacity_admit_reason() { printf '%s' "$CC_ADMIT_REASON"; }

# ── record ONE row into the IDL ────────────────────────────────────────────────────────────────
# The IDL is where cc-dispatch already files its `reason:"capacity"` rows, so `cc-idl` becomes the
# ONE query surface over admission across every gated path — the coverage question §12.1 could not
# answer and §9.5.1 had to retract a claim over.
#
# SELF-CONTAINED ON PURPOSE — it must NOT source hooks/lib/idl-log.sh. That lib defines a global
# `log_idl`, and `boot-resume.sh` (one of the four callers this library exists to gate) defines its
# OWN `log_idl` emitting `tool:"boot-resume"` rows. Sourcing would silently overwrite the caller's
# writer and corrupt its records — a library that rewrites its caller's telemetry to install a gate
# is a worse defect than the ungated spawn. What idl-log.sh actually protects is the invariant, not
# the function: jq-encode EVERY field, because ONE malformed line aborts the cc-audit `jq -rs` slurp,
# which then reads as "no records" and silently flips the abstain alarm GREEN. That invariant is
# honoured here by construction (`jq -cn --arg` only) — no jq, no row, never a raw append.
_cc_admit_emit() { # $1=verdict admit|refuse  $2=basis  $3=caller  $4=what  $5=detail  $6=term(optional)
  local idl ts
  idl="${CC_ADMIT_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
  command -v jq >/dev/null 2>&1 || return 0
  mkdir -p "$(dirname "$idl")" 2>/dev/null || true
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  # `gate` is carried on BOTH verdicts (§9.5.1): admits and refusals must be selectable by ONE
  # predicate, never two hand-written asymmetric ones, or the denominator silently picks up rows
  # from a different gate — the exact mis-derivation §9.5.1 had to retract.
  # `presence` and `reserve` ride on EVERY row, admits included, for §9.5.1's reason: a ratio computed
  # over these rows is meaningless unless the population can be split by what was actually evaluated.
  # An admit at reserve 0 (operator absent) and an admit at reserve 6 (operator present) are different
  # events, and without the field the only visible difference is the free text of `detail`.
  # `terms` and `blind` ride on EVERY row for §9.5.1's reason, and they are what kept the shared
  # `basis` vocabulary honest when Wave D added a third and fourth term. `basis` has four values that
  # capacity_gate() also emits, and it can therefore only ever describe the load/headroom PAIR; once
  # `segments` and `active` exist, a row reading `headroom-only` no longer tells a reader which terms
  # were in force. So the switches' state is recorded explicitly:
  #   terms  the terms ENABLED for this evaluation — not necessarily all evaluated, because the gate
  #          short-circuits at the first refusal. This is the field to split a population on.
  #   blind  the enabled terms whose instrument could not be read. A term that silently stopped
  #          evaluating reads back as a healthy admit — the 222-dead-sysctl-rows shape — so its
  #          blindness is named on the row rather than inferred from the absence of a number.
  jq -cn --arg ts "$ts" --arg disp "$( [ "$1" = admit ] && echo admitted || echo refused )" \
         --arg v "$1" --arg b "$2" --arg c "$3" --arg w "$4" --arg d "$5" --arg t "${6:-}" \
         --arg sid "${CC_ADMIT_SID:-?}" --arg pres "${CC_ADMIT_PRESENCE:-}" \
         --arg rsv "${CC_ADMIT_RESERVE:-}" --arg tms "${CC_ADMIT_TERMS:-}" \
         --arg bld "${CC_ADMIT_BLIND:-}" \
    '{ts:$ts,hook:"capacity-admit",sid:$sid,disposition:$disp,reason:"capacity",
      gate:"capacity-admit",verdict:$v,basis:$b,caller:$c,what:$w,detail:$d}
     + (if $t    == "" then {} else {term:$t} end)
     + (if $pres == "" then {} else {presence:$pres} end)
     + (if $rsv  == "" then {} else {reserve:$rsv} end)
     + (if $tms  == "" then {} else {terms:$tms} end)
     + (if $bld  == "" then {} else {blind:$bld} end)' >> "$idl" 2>/dev/null || true
  return 0
}

# The enabled-term list and the blind-term list for ONE evaluation. Both are rebuilt at the top of
# every call — a stale list carried across two evaluations in one process would attribute one
# decision's blindness to another (memory init-state-is-not-runtime-state).
CC_ADMIT_TERMS=""
CC_ADMIT_BLIND=""
_cc_admit_note_blind() { # $1=term name
  case "$CC_ADMIT_BLIND" in
    "")   CC_ADMIT_BLIND="$1" ;;
    *"$1"*) : ;;
    *)    CC_ADMIT_BLIND="${CC_ADMIT_BLIND},$1" ;;
  esac
}

# ── THE PRESENCE CONSULT (§W3 item 1) ──────────────────────────────────────────────────────────
# The beat is read HERE, at spawn, which is the whole point of the item: hooks/lib/cc-beat.sh had two
# consumers in the tree and both were teardown-time, so the box knew the operator was present and no
# spawner asked. This resolves the measurement library the same three-path way every other sibling is
# resolved (script-relative FIRST, so the term goes live on the trunk fast-forward rather than waiting
# behind a deploy it cannot trigger — the deployed-layer-bootstrap-circle), and it is ABSENT-TOLERANT:
# a missing library yields presence `unavailable` and reserve 0, i.e. the gate behaves exactly as it
# did before this term existed. Inertness is LOUD (it lands in every row's `presence` field), never a
# silent tightening — a reserve applied on a measurement that could not be taken would refuse spawns
# for a reason nothing on disk could later explain.
_CC_ADMIT_SP=""
_cc_admit_load_presence() { # → 0 when cc_sp_* is available
  command -v cc_sp_reserve_slots >/dev/null 2>&1 && return 0
  [ -n "$_CC_ADMIT_SP" ] && return 1          # resolved once already and failed; do not re-fork
  local here d
  here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || here=""
  if [ -n "${CC_ADMIT_PRESENCE_LIB:-}" ]; then
    if [ -f "$CC_ADMIT_PRESENCE_LIB" ]; then
      # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
      . "$CC_ADMIT_PRESENCE_LIB" 2>/dev/null || true
    fi
    command -v cc_sp_reserve_slots >/dev/null 2>&1 && return 0
    _CC_ADMIT_SP=miss; return 1
  fi
  for d in "${here:-.}/spawn-presence.sh" \
           "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/spawn-presence.sh" \
           "$HOME/.claude/scripts/lib/spawn-presence.sh"; do
    if [ -f "$d" ]; then
      # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
      . "$d" 2>/dev/null || true
      command -v cc_sp_reserve_slots >/dev/null 2>&1 && return 0
    fi
  done
  _CC_ADMIT_SP=miss
  return 1
}

# Sets CC_ADMIT_PRESENCE / CC_ADMIT_RESERVE / CC_ADMIT_RESERVE_GB / CC_ADMIT_RESERVE_SLOTS.
# Called ONCE per evaluation, before the terms, so every row of that evaluation carries the same
# reading — a second call could straddle a turn boundary and record two different worlds for one
# decision (memory init-state-is-not-runtime-state).
_cc_admit_presence_read() {
  CC_ADMIT_PRESENCE=""; CC_ADMIT_RESERVE=""; CC_ADMIT_RESERVE_GB=0; CC_ADMIT_RESERVE_SLOTS=0
  if [ "${CC_ADMIT_RESERVE_TERM:-on}" = off ]; then CC_ADMIT_PRESENCE="term-off"; return 0; fi
  if ! _cc_admit_load_presence; then CC_ADMIT_PRESENCE="unavailable"; return 0; fi
  CC_ADMIT_PRESENCE="$(cc_sp_operator_state "${CC_ADMIT_SID:-}" 2>/dev/null || printf 'unknown')"
  case "$CC_ADMIT_PRESENCE" in self|present|absent|unknown) : ;; *) CC_ADMIT_PRESENCE=unknown ;; esac
  CC_ADMIT_RESERVE_SLOTS="$(cc_sp_reserve_slots "$CC_ADMIT_PRESENCE" 2>/dev/null || printf 0)"
  CC_ADMIT_RESERVE_GB="$(cc_sp_reserve_gb "$CC_ADMIT_PRESENCE" 2>/dev/null || printf 0)"
  cc_hw_is_int "$CC_ADMIT_RESERVE_SLOTS" || CC_ADMIT_RESERVE_SLOTS=0
  cc_hw_is_int "$CC_ADMIT_RESERVE_GB"    || CC_ADMIT_RESERVE_GB=0
  CC_ADMIT_RESERVE="${CC_ADMIT_RESERVE_SLOTS} slots + ${CC_ADMIT_RESERVE_GB}GB"
  return 0
}
CC_ADMIT_PRESENCE=""
CC_ADMIT_RESERVE=""
CC_ADMIT_RESERVE_GB=0
CC_ADMIT_RESERVE_SLOTS=0

# ── the bound (§9's law): consecutive refusals per caller ──────────────────────────────────────
# State is a single integer per caller. Deliberately NOT a timestamp: this must behave identically
# in a PreToolUse hook (cannot sleep — a slot is held), in a launchd job at boot, and in a live
# pane. A count is the only bound with that property, and it is what makes the expiry an EVENT.
_cc_admit_state_file() { # $1=caller → path, or empty when the caller id is unusable
  local dir="${CC_ADMIT_STATE_DIR:-$HOME/.claude/autonomy/capacity-admit}"
  case "$1" in ''|*[!A-Za-z0-9._-]*) return 0 ;; esac
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s/%s.refusals' "$dir" "$1"
}

_cc_admit_reset() { local f; f="$(_cc_admit_state_file "$1")"; [ -n "$f" ] && : > "$f" 2>/dev/null; return 0; }

# ── the page: a refusal that nobody sees is a silent drop ──────────────────────────────────────
_cc_admit_page() { # $1=text
  local n; n="${CC_ADMIT_NOTIFY_BIN:-}"
  [ -n "$n" ] || n="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/cc-notify"
  [ -x "$n" ] || n="$HOME/.claude/bin/cc-notify"
  [ -x "$n" ] || return 0
  "$n" --page "$1" >/dev/null 2>&1 || true
  return 0
}

# ── the gate ───────────────────────────────────────────────────────────────────────────────────
cc_capacity_admit() { # $1=caller  $2=what   → 0 admit / 9 refuse
  local caller="${1:-unknown}" what="${2:-spawn}"
  local ncpu load ceiling lpc verdict floor head_gb sysctl_bin budget detail
  local seg_row seg_pct seg_segs seg_lim seg_ceiling act act_ceiling

  # The enabled-term list for THIS evaluation, rebuilt every call. See _cc_admit_emit's header: once
  # the gate carries four terms, `basis` (shared with capacity_gate, which has two) can no longer say
  # which were in force, and a ratio computed without that split is the §9.5.1 defect.
  CC_ADMIT_TERMS=""; CC_ADMIT_BLIND=""
  [ "${CC_ADMIT_LOAD_TERM:-on}"     = off ] || CC_ADMIT_TERMS="load"
  [ "${CC_ADMIT_HEADROOM_TERM:-on}" = off ] || CC_ADMIT_TERMS="${CC_ADMIT_TERMS:+$CC_ADMIT_TERMS,}headroom"
  [ "${CC_ADMIT_SEGMENT_TERM:-on}"  = off ] || CC_ADMIT_TERMS="${CC_ADMIT_TERMS:+$CC_ADMIT_TERMS,}segments"
  [ "${CC_ADMIT_ACTIVE_TERM:-on}"   = off ] || CC_ADMIT_TERMS="${CC_ADMIT_TERMS:+$CC_ADMIT_TERMS,}active"

  if [ "${CC_ADMIT_GATE:-on}" = off ]; then
    # Recorded, never silent: an operator override or a pinned test suite must not read back later
    # as a healthy admit. This is the row that keeps "the gate was OFF" out of the measured population.
    CC_ADMIT_REASON="capacity-admit: OFF (CC_ADMIT_GATE=off) — no term evaluated"
    _cc_admit_emit admit gate-off "$caller" "$what" "CC_ADMIT_GATE=off"; return 0
  fi

  # Probes + defaults come from the SHARED TERMS above — the same resolver, the same reads and the
  # same literals capacity_gate() expands, so a PATH fix or a ceiling change lands once. The
  # RESOLVED BINARY is still named in every fail-open row here, not just the failing key:
  # handoff-fire's 222 dead rows all carried one identical string, so the ledger could not say
  # whether the next one was the same PATH miss or a NEW cause (exec-deny, sandbox, a sysctl that
  # stopped answering) — states that read alike and have different fixes.
  # ONE presence reading per evaluation, taken before any term so every row of this decision agrees.
  _cc_admit_presence_read

  sysctl_bin="$(cc_hw_resolve_sysctl "${CC_ADMIT_SYSCTL:-}")"
  ncpu="$(cc_hw_ncpu "$sysctl_bin")"
  load="$(cc_hw_load1 "$sysctl_bin")"
  [ -n "${CC_ADMIT_LOADAVG_OVERRIDE:-}" ] && load="$CC_ADMIT_LOADAVG_OVERRIDE"
  ceiling="${CC_ADMIT_MAX_LOAD_PER_CORE:-$CC_HW_DEFAULT_MAX_LOAD_PER_CORE}"
  budget="${CC_ADMIT_BUDGET:-3}"

  # A bad budget must fail to the side that keeps the gate BOUNDED — i.e. admit. A typo that made
  # this gate unbounded would re-create the §12.2 outage, so the unsafe direction is refusal.
  # NOT a shared term: the bound is this gate's own policy and capacity_gate() deliberately has none.
  # Checked FIRST because it is the only validator that is not one term's own input.
  if ! cc_hw_is_int "$budget"; then
    CC_ADMIT_REASON="capacity-admit: bad CC_ADMIT_BUDGET ('$budget') -> ADMIT (fail-open)"
    _cc_admit_emit admit fail-open "$caller" "$what" "bad CC_ADMIT_BUDGET ('$budget') — bound unusable"
    _cc_admit_reset "$caller"; return 0
  fi

  # ── the LOAD TERM'S OWN INPUTS, validated only when that term is enabled ────────────────────────
  # Until Wave D this block ran unconditionally, and that was invisible while the gate had two terms
  # and both needed a live box. With four terms it is a deletion: `sysctl` lives in /usr/sbin, which
  # a launchd PATH lacks, and that ONE miss is the most-measured failure in this file's history —
  # 222 of 239 capacity rows over 2026-08-03..06 read `hw.ncpu unreadable ('')`. Returning fail-open
  # there also deletes the headroom, segment, active and reserve terms, none of which asked about
  # hw.ncpu; on the Agent-tool path, which turns the load term OFF on purpose, it deletes the whole
  # gate over an input that path does not use. A term's unreadable input may only blind THAT term.
  if [ "${CC_ADMIT_LOAD_TERM:-on}" != off ]; then
    if ! cc_hw_is_int "$ncpu"; then
      CC_ADMIT_REASON="capacity-admit: hw.ncpu unreadable ('$ncpu') via $sysctl_bin -> ADMIT (fail-open)"
      _cc_admit_note_blind load
      _cc_admit_emit admit fail-open "$caller" "$what" "hw.ncpu unreadable ('$ncpu') via $sysctl_bin"
      _cc_admit_reset "$caller"; return 0
    fi
    if ! cc_hw_is_num "$load"; then
      CC_ADMIT_REASON="capacity-admit: vm.loadavg unreadable ('$load') via $sysctl_bin -> ADMIT (fail-open)"
      _cc_admit_note_blind load
      _cc_admit_emit admit fail-open "$caller" "$what" "vm.loadavg unreadable ('$load') via $sysctl_bin"
      _cc_admit_reset "$caller"; return 0
    fi
    if ! cc_hw_is_num "$ceiling"; then
      CC_ADMIT_REASON="capacity-admit: bad CC_ADMIT_MAX_LOAD_PER_CORE ('$ceiling') -> ADMIT (fail-open)"
      _cc_admit_note_blind load
      _cc_admit_emit admit fail-open "$caller" "$what" "bad CC_ADMIT_MAX_LOAD_PER_CORE ('$ceiling')"
      _cc_admit_reset "$caller"; return 0
    fi
    if [ "$ncpu" -le 0 ]; then
      CC_ADMIT_REASON="capacity-admit: hw.ncpu=0 -> ADMIT (fail-open)"
      _cc_admit_note_blind load
      _cc_admit_emit admit fail-open "$caller" "$what" "hw.ncpu=0"
      _cc_admit_reset "$caller"; return 0
    fi
  fi

  # ── load term. Switchable PER CALLER, and the Agent-tool path turns it OFF deliberately — see
  #    hooks/agent-teams-enforce.sh. §8.5.7 measured loadavg swinging 2.05x at CONSTANT session
  #    count (it is dominated by the TUI renderer, WindowServer and macOS scanning), and §12.2
  #    measured 2.16/core on a box with 13 sessions, 24 GB free and 0 B compressor — perfectly
  #    healthy. On a low-volume recovery path that imprecision costs a delayed resume; on the
  #    HIGHEST-volume spawn surface it would throttle the fleet's main work path on a proxy the
  #    plan itself calls bad. Turning it off there is not a weaker gate, it is the term that is
  #    actually attributable to what is being spawned.
  if [ "${CC_ADMIT_LOAD_TERM:-on}" = off ]; then
    lpc="n/a"
  else
    verdict="$(cc_hw_load_verdict "$load" "$ncpu" "$ceiling")"
    lpc="${verdict#* }"; verdict="${verdict%% *}"
    if [ "$verdict" = REFUSE ]; then
      detail="load ${load} on ${ncpu} cores = ${lpc}/core > ceiling ${ceiling}/core"
      _cc_admit_spend "$caller" "$what" "$budget" "$detail" "load"; return $?
    fi
  fi

  # ── headroom term. Runs ONLY once the load term admitted, so a load refusal keeps its own
  #    numbers; this term can only narrow admission further. Memory headroom is the SHEDDABLE,
  #    session-attributable quantity §8.5.2's retraction asked for — unlike loadavg, a session's
  #    footprint IS reclaimable by closing it, so refusing here can actually change what it reads.
  if [ "${CC_ADMIT_HEADROOM_TERM:-on}" = off ]; then
    if [ -z "$CC_ADMIT_TERMS" ]; then
      # EVERY term off = no term evaluated at all. This is `gate-off` however it was spelled, and it
      # must record as such: a row reading `load-only` with the load term also off would count a
      # blind evaluation as a real one, which is the §9.5.1 population defect exactly.
      # THE CONDITION IS `$CC_ADMIT_TERMS` EMPTY, not "load and headroom are off". Wave D added two
      # more terms, and the old two-term test would have recorded a real segment/active evaluation as
      # `gate-off` — the same defect this branch exists to prevent, arriving from the other side.
      CC_ADMIT_REASON="capacity-admit: ADMIT — every term off, nothing evaluated"
      _cc_admit_emit admit gate-off "$caller" "$what" \
        "CC_ADMIT_LOAD_TERM/HEADROOM_TERM/SEGMENT_TERM/ACTIVE_TERM all off"
      _cc_admit_reset "$caller"; return 0
    fi
    floor=""; head_gb=""
  else
    floor="${CC_ADMIT_MIN_HEADROOM_GB:-$CC_HW_DEFAULT_MIN_HEADROOM_GB}"
    if [ -n "${CC_ADMIT_HEADROOM_OVERRIDE:-}" ]; then
      head_gb="$CC_ADMIT_HEADROOM_OVERRIDE"
    else
      head_gb="$(cc_hw_headroom_gb)" || head_gb=""
    fi
    if ! cc_hw_is_num "$floor"; then
      CC_ADMIT_REASON="capacity-admit: bad CC_ADMIT_MIN_HEADROOM_GB ('$floor') -> ADMIT (fail-open)"
      _cc_admit_note_blind headroom
      _cc_admit_emit admit fail-open "$caller" "$what" "bad CC_ADMIT_MIN_HEADROOM_GB ('$floor')"
      _cc_admit_reset "$caller"; return 0
    fi
  fi
  if [ -n "$floor" ]; then
    if ! cc_hw_is_num "$head_gb"; then
      CC_ADMIT_REASON="capacity-admit: reclaimable headroom unreadable ('$head_gb') -> ADMIT (fail-open)"
      _cc_admit_note_blind headroom
      _cc_admit_emit admit fail-open "$caller" "$what" "reclaimable headroom unreadable ('$head_gb')"
      _cc_admit_reset "$caller"; return 0
    fi
    if [ "$(cc_hw_headroom_verdict "$head_gb" "$floor")" = REFUSE ]; then
      detail="reclaimable ${head_gb}GB < floor ${floor}GB"
      _cc_admit_spend "$caller" "$what" "$budget" "$detail" "headroom"; return $?
    fi
  fi

  # ── SEGMENT TERM (Wave D) — the memory term that can BIND ───────────────────────────────────────
  # Runs after headroom because the two are complements, not alternatives: headroom answers "can a
  # new session take its RAM without swapping", segments answers "is this box already IN the burst
  # regime that kills it". A steady-state session compresses nothing, so segments alone is blind to
  # plain residency exhaustion; and headroom alone is what fired 0 times in 127 refusals.
  #
  # THE CEILING IS THIS GATE'S OWN POLICY, like the budget — deliberately NOT a CC_HW_DEFAULT_*
  # shared constant, because capacity_gate() does not carry this term and "a constant nothing reads
  # is not a shared term, it is a comment" (coverage case 26's own doctrine).
  #
  # 50% IS PROVISIONAL AND SAYS SO. The sentinel's 15% is NOT reusable here: it is the LEVEL half of
  # a level-AND-rate conjunction (>15% of limit AND >600 segments/s), and a single-sample gate that
  # cannot take a rate would be importing half a predicate — this box "idles well under 15%", so 15
  # alone would refuse on ordinary builds, the fail-closed-degradation-as-amplifier direction. 50 sits
  # far above the measured idle band and far below the 100% observed at panic (the quiet-box control
  # read 0.00%). Every row carries the measured pct, admits included, so the real distribution is
  # re-derivable rather than argued — DO NOT quote this paragraph, re-derive:
  #   cc-idl … | jq -rs 'map(select(.gate=="capacity-admit") | .detail | capture("segments (?<p>[0-9.]+)%") .p | tonumber) | sort'
  if [ "${CC_ADMIT_SEGMENT_TERM:-on}" != off ]; then
    seg_ceiling="${CC_ADMIT_MAX_SEGMENT_PCT:-50}"
    if [ -n "${CC_ADMIT_SEGMENT_OVERRIDE:-}" ]; then
      seg_pct="$CC_ADMIT_SEGMENT_OVERRIDE"; seg_segs="?"; seg_lim="?"
    else
      seg_row="$(cc_hw_compressor_segment_pct "$sysctl_bin")" || seg_row=""
      seg_pct="${seg_row%% *}"; seg_segs="${seg_row#* }"; seg_lim="${seg_segs#* }"; seg_segs="${seg_segs%% *}"
    fi
    # A BLIND TERM IS A NOTE, NEVER AN EARLY RETURN. This is the one structural rule a term added
    # after the fact must follow: failing open out of the function here would delete the active and
    # reserve terms below over an input they never asked for — the same deletion the load-input block
    # above was restructured to stop. Blindness is recorded (`blind`) so a window in which this term
    # was not evaluating is greppable, never indistinguishable from a quiet box.
    if ! cc_hw_is_num "$seg_pct" || ! cc_hw_is_num "$seg_ceiling"; then
      _cc_admit_note_blind segments
      seg_pct=""
    elif [ "$(cc_hw_segment_verdict "$seg_pct" "$seg_ceiling")" = REFUSE ]; then
      detail="compressor segments ${seg_pct}% of limit (${seg_segs} of ${seg_lim}) > ceiling ${seg_ceiling}%"
      _cc_admit_spend "$caller" "$what" "$budget" "$detail" "segments"; return $?
    fi
  else
    seg_pct=""
  fi

  # ── ACTIVE-CONCURRENCY TERM (Wave D) — the ceiling the design point actually needs ──────────────
  # "~10 active" was the arithmetic every capacity claim rested on and NOTHING enforced it: axis 13
  # names that circularity outright ("the ranking assumes the outcome of the wave its own conclusion
  # deprioritises"), and axis 10's F3 is the failure it produces — a fleet-wide wake turns 140 idle
  # residents into 140 concurrent turns, which no spawn gate keyed on residency can even see.
  #
  # 8 is the top of the measured band. Axis 09: 2.5-5 runnable threads per genuinely-ACTIVE session
  # (load1 27.4 -> 44.4 at 9 all-active) against the load-20 gate ⇒ ~4-8 concurrent actives, which is
  # also what all 127/127 historic gate refusals correspond to. The TOP of the band is deliberate:
  # this term refuses real work, so it must bind where the evidence is unambiguous, and the load and
  # segment terms above already cover the middle of the band from their own directions.
  #
  # THE CENSUS IS A PROVEN LOWER BOUND (scripts/lib/spawn-presence.sh § THE ACTIVE POPULATION), so
  # this term under-refuses rather than refusing on unproven activity — the same direction rule the
  # reserve follows. An unavailable library or an unreadable census is a NOTED blindness, not a
  # deletion of the terms below it.
  act=""
  if [ "${CC_ADMIT_ACTIVE_TERM:-on}" != off ]; then
    act_ceiling="${CC_ADMIT_ACTIVE_CEILING:-8}"
    if _cc_admit_load_presence && command -v cc_sp_active >/dev/null 2>&1; then
      act="$(cc_sp_active 2>/dev/null || true)"
    fi
    if ! cc_hw_is_int "$act" || ! cc_hw_is_int "$act_ceiling"; then
      _cc_admit_note_blind active
      act=""
    elif [ $(( act + 1 )) -gt "$act_ceiling" ]; then
      detail="${act} sessions mid-turn + 1 > active ceiling ${act_ceiling}"
      _cc_admit_spend "$caller" "$what" "$budget" "$detail" "active"; return $?
    fi
  fi

  # ── THE RESERVE (§W3 items 1/4/5) — the operator's floor, in the dimension the box binds on ────
  # Runs LAST and only over an otherwise-admitting box, so a plain saturation refusal keeps its own
  # numbers and its own term; this narrows admission only for the caller that is NOT the operator.
  # The term is REACHED only when the presence read succeeded — `unavailable`/`term-off` leave the
  # gate exactly as it was before this term existed.
  #
  # TWO DIMENSIONS, because a count alone is inert exactly when the operator complains. Measured
  # 2026-08-12 while building this: 10-11 live session trees against a MEASURED 54-session floor with
  # 30 GB reclaimable. A pure count reserve never fires at that occupancy; memory headroom is what the
  # box actually binds on, and §8.5.2's retraction certified it as the one quantity that is both
  # SHEDDABLE and SESSION-ATTRIBUTABLE. So autonomy must leave the operator's next session's worth of
  # RAM standing (`reserve-headroom`) as well as its slots (`reserve-slots`).
  #
  # WHY THE TERMS STAY DISTINGUISHABLE IN THE ROW: `headroom` above means the box is genuinely out —
  # the operator's own fire would have been refused too. `reserve-headroom` means the box had room and
  # autonomy yielded. Folding them would make "did the reserve cost us anything?" unanswerable, which
  # is the §9.5.1 population defect in miniature.
  if [ "$CC_ADMIT_PRESENCE" = self ] || [ "$CC_ADMIT_PRESENCE" = present ] \
  || [ "$CC_ADMIT_PRESENCE" = absent ] || [ "$CC_ADMIT_PRESENCE" = unknown ]; then
    local eff_floor ceiling_n trees limit act_limit act_reserve
    if [ -n "$floor" ] && [ "$CC_ADMIT_RESERVE_GB" -gt 0 ] 2>/dev/null; then
      eff_floor="$(awk -v f="$floor" -v r="$CC_ADMIT_RESERVE_GB" 'BEGIN { printf "%.2f", f + r }')"
      if [ "$(cc_hw_headroom_verdict "$head_gb" "$eff_floor")" = REFUSE ]; then
        detail="reclaimable ${head_gb}GB < floor ${floor}GB + operator reserve ${CC_ADMIT_RESERVE_GB}GB = ${eff_floor}GB (operator ${CC_ADMIT_PRESENCE})"
        _cc_admit_spend "$caller" "$what" "$budget" "$detail" "reserve-headroom"; return $?
      fi
    fi
    # ── reserve-active (Wave D) — the operator's slot in the dimension that binds FIRST ───────────
    # Same law as reserve-headroom, in the ACTIVE dimension: `active` above means the box is out and
    # the operator's own turn would contend too; `reserve-active` means there was room and autonomy
    # yielded. Distinct terms because they have different cures.
    #
    # ITS OWN CONSTANT, and small (1). cc_sp_reserve_slots returns 2-6 — correct against a 54-session
    # RESIDENT ceiling and absurd against an active ceiling of 8, where it would cut autonomy to two
    # concurrent turns. And it applies ONLY on PROVEN presence: `absent`/`unknown` carry no base
    # reserve here (unlike the slot reserve, whose base is 2), because this is already the tightest
    # term on the gate and a standing base would permanently spend an eighth of the design point on a
    # human who is provably not there. `self` reserves nothing — the operator spending their own
    # capacity is the reserve's beneficiary, not its subject.
    if [ -n "$act" ] && [ "$CC_ADMIT_PRESENCE" = present ]; then
      act_reserve="${CC_ADMIT_ACTIVE_RESERVE:-1}"
      if cc_hw_is_int "$act_reserve" && cc_hw_is_int "${act_ceiling:-}"; then
        act_limit=$(( act_ceiling - act_reserve ))
        [ "$act_limit" -lt 0 ] && act_limit=0
        if [ $(( act + 1 )) -gt "$act_limit" ]; then
          detail="${act} sessions mid-turn + 1 > active ceiling ${act_ceiling} − operator reserve ${act_reserve} = ${act_limit} (operator ${CC_ADMIT_PRESENCE})"
          _cc_admit_spend "$caller" "$what" "$budget" "$detail" "reserve-active"; return $?
        fi
      fi
    fi
    # The session-count ceiling — the ONE place `~15` is replaced by the measured 54-session floor
    # (scripts/lib/spawn-presence.sh § THE CEILING). Charged against a `ps` TREE census, never the
    # beat: measured 2026-08-12, zero beats were younger than 60 s while ten sessions were live,
    # because the beat is written at turn boundaries and the busiest sessions are the quietest.
    ceiling_n="${CC_ADMIT_SESSION_CEILING:-${CC_SP_CEILING:-${CC_SP_DEFAULT_CEILING:-54}}}"
    if cc_hw_is_int "$ceiling_n" && [ "$CC_ADMIT_RESERVE_SLOTS" -ge 0 ] 2>/dev/null; then
      trees="$(cc_sp_trees 2>/dev/null || true)"
      if cc_hw_is_int "$trees"; then
        limit=$(( ceiling_n - CC_ADMIT_RESERVE_SLOTS ))
        [ "$limit" -lt 0 ] && limit=0
        if [ $(( trees + 1 )) -gt "$limit" ]; then
          detail="${trees} live session trees + 1 > ceiling ${ceiling_n} − operator reserve ${CC_ADMIT_RESERVE_SLOTS} = ${limit} (operator ${CC_ADMIT_PRESENCE})"
          _cc_admit_spend "$caller" "$what" "$budget" "$detail" "reserve-slots"; return $?
        fi
      else
        # An unreadable census is a fail-OPEN that must be VISIBLE, not an invisible skip: it is the
        # 222-dead-sysctl-rows shape exactly — a term that silently stopped evaluating reads back as a
        # healthy admit. Marked in `reserve`, which rides on the admit row this falls through to, so a
        # window where the census was blind is greppable rather than indistinguishable from a quiet box.
        CC_ADMIT_RESERVE="${CC_ADMIT_RESERVE} · census UNREADABLE"
      fi
    fi
  fi

  # `measured` means what a naive reader assumes "admit" means: EVERY ENABLED term read a live
  # instrument and cleared. A caller running one term gets `headroom-only`/`load-only` instead, so a
  # single-term window can never be counted as evidence that both were exercised.
  #
  # THOSE TWO NAMES DESCRIBE THE LOAD/HEADROOM PAIR ONLY, and that is not sloppiness: `basis` is the
  # vocabulary SHARED with capacity_gate(), which carries exactly that pair, so it cannot grow a
  # value per term without corrupting the field for the other gate (coverage case 27 is the ratchet:
  # capacity_gate's vocabulary must stay a SUBSET of this one). `terms` is therefore the
  # authoritative field for which terms were in force, and `blind` for which of them could not read.
  #
  # ⚠️ AMENDS §9.5.1's INSTRUCTION AT THE TOP OF THIS FILE: split on `basis` AND `blind`. Before
  # Wave D a blind term was IMPOSSIBLE — any unreadable input fail-opened the whole gate and
  # returned, so `measured` could promise that every enabled term read a live instrument. With four
  # terms that return is itself the defect (one dead probe deleting three healthy terms), so
  # blindness became a per-term state, and the promise moved to the conjunction: a row is evidence
  # that a term was exercised only when `terms` names it and `blind` does not.
  #
  # The cleared terms' NUMBERS ride on the admit row, not just the refusal's: §9.5.1's rule is that
  # an admit with no numbers is worse than a refusal with none, because nothing about it looks wrong.
  # That is also what makes the provisional segment ceiling re-derivable from the ledger.
  if [ "${CC_ADMIT_LOAD_TERM:-on}" = off ]; then
    detail="load term off"
  else
    detail="load ${load} on ${ncpu} cores = ${lpc}/core (ceiling ${ceiling}/core)"
  fi
  if [ -n "$floor" ]; then
    detail="${detail} · reclaimable ${head_gb}GB (floor ${floor}GB)"
  else
    detail="${detail} · headroom term off"
  fi
  [ -n "$seg_pct" ] && detail="${detail} · segments ${seg_pct}% of limit (ceiling ${seg_ceiling}%)"
  [ -n "$act" ]     && detail="${detail} · ${act} sessions mid-turn (active ceiling ${act_ceiling})"
  [ -n "$CC_ADMIT_BLIND" ] && detail="${detail} · BLIND: ${CC_ADMIT_BLIND}"
  CC_ADMIT_REASON="capacity-admit: ADMIT — ${detail}"
  if [ "${CC_ADMIT_LOAD_TERM:-on}" = off ] && [ -n "$floor" ]; then
    _cc_admit_emit admit headroom-only "$caller" "$what" "$detail"
  elif [ "${CC_ADMIT_LOAD_TERM:-on}" != off ] && [ -z "$floor" ]; then
    _cc_admit_emit admit load-only "$caller" "$what" "$detail"
  else
    # Both of the pair ran, or NEITHER did while a Wave D term carried the evaluation. `measured` is
    # correct under its own definition either way — every enabled term cleared — and `terms` is what
    # says which. There is deliberately no fifth basis value: see the paragraph above.
    _cc_admit_emit admit measured "$caller" "$what" "$detail"
  fi
  _cc_admit_reset "$caller"
  return 0
}

# ── spend one unit of budget, or convert the standing state into an event ──────────────────────
# This is the entire §9 law in one function: a would-be refusal is only allowed to BE a refusal
# while budget remains. Past it the gate admits and pages, so a saturated box delays a spawn and
# can never stand as a permanent refusal — the §12.2 outage, made structurally unreachable.
_cc_admit_spend() { # $1=caller $2=what $3=budget $4=detail $5=term → 0 admit / 9 refuse
  local caller="$1" what="$2" budget="$3" detail="$4" term="$5" sf n rc
  sf="$(_cc_admit_state_file "$caller")"
  if [ -z "$sf" ]; then
    # An unusable caller id means the bound cannot be tracked, and an UNTRACKED bound is an
    # UNBOUNDED gate. Refusing here would convict on our own bad wiring, so admit and say so.
    CC_ADMIT_REASON="capacity-admit: ADMIT (fail-open) — caller id '$caller' cannot key the budget; bound untrackable"
    _cc_admit_emit admit fail-open "$caller" "$what" "caller id unusable — bound untrackable ($detail)"
    return 0
  fi
  # The counter itself is cc_hw_budget_charge (a SHARED TERM as of 2026-08-12) — one bound
  # implementation, so the operator's gate in handoff-fire.sh and this one cannot drift on the
  # arithmetic. Everything below is this gate's POLICY over that verdict: the sentence, the row and
  # the page are its own.
  cc_hw_budget_charge "$sf" "$budget"; rc=$?
  if [ "$rc" -eq 1 ]; then
    CC_ADMIT_REASON="capacity-admit: ADMIT (fail-open) — bound untrackable for '$caller'; a bound that cannot be tracked is an UNBOUNDED gate"
    _cc_admit_emit admit fail-open "$caller" "$what" "bound untrackable — budget '$budget' unusable ($detail)"
    return 0
  fi
  n="$CC_HW_BUDGET_N"
  if [ "$rc" -eq 10 ]; then
    CC_ADMIT_REASON="capacity-admit: ADMIT (budget expired after ${budget} consecutive refusals) — ${detail}"
    _cc_admit_emit admit budget-expired "$caller" "$what" \
      "${term} term over after ${budget} consecutive refusals — admitting and paging: ${detail}" "$term"
    _cc_admit_page "⚠️ capacity-admit: ${caller} spent its ${budget}-refusal budget and is ADMITTING '${what}' into a saturated box — ${detail}. Shed load (close finished panes) or raise the bar."
    return 0
  fi
  # The counter write and the reset both live in cc_hw_budget_charge — deliberately NOT repeated here.
  # Two writers over one state file is how a bound starts disagreeing with itself.
  CC_ADMIT_REASON="capacity-admit: REFUSING ${what} — ${detail} (refusal ${n} of ${budget}; once the budget is spent the next evaluation ADMITS and pages)"
  # basis stays `measured` — BOTH instruments read fine; it is the box that is over, not the probe.
  # WHICH term refused is a separate field: folding it into `basis` would corrupt the one vocabulary
  # §9.5.1 requires you to split on before believing any ratio computed from these rows.
  _cc_admit_emit refuse measured "$caller" "$what" "${detail} (refusal ${n} of budget ${budget})" "$term"
  return 9
}
