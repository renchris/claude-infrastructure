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
# 🚨 2.0/core WAS NEVER DERIVED, AND NO DERIVATION IS REACHABLE ON THIS AXIS. This line used to read
# "2.0/core is §9.5's measured ceiling". §9.5 contains no derivation: it records the gate ADMITTING
# at 1.55/core and REFUSING at 4.0/core — a demonstration that a threshold thresholds — and its own
# closing paragraph then says the gate keys on a quantity that is NOT session-attributable, i.e. the
# section undercuts the term it was cited as justifying. The origin commit (`feat(handoff-fire):
# machine-capacity admission gate at the spawn chokepoint`, 2026-07-29 — cite by SUBJECT, a land
# rebases) measured its motivating incident at 2.72/core and picked 2.0 with no stated rule, so the
# shipped ceiling sits BELOW the only incident that produced it.
#
# The missing derivation cannot be supplied later, either: scripts/capacity-alarm.sh's rung-7 header
# records that THE SURVIVED POPULATION CONTAINS THE FATAL VALUE — fatal 2026-08-05 at 2.53/core
# against 13 consecutive survived samples spanning 2.92-5.98/core, plus 42 h at 2.5/core with no
# panic — so "set the ceiling from a measured failure point" has no solution on this axis. That is
# that file's own conclusion, executable in its selftest (5.98/core pinned as a known false ALARM).
#
# 🚨 THIS IS NOT A CASE TO RAISE THE NUMBER. `fix(fire-gate): load1 does not move with the spawn it
# was gating` (f944d6e3, 2026-08-20, ancestor of trunk) established the stronger fact: an additional
# RESIDENT session moves the 1-min runnable count by ~0, so NO value of this literal can make the
# term correct — the INPUT is wrong, not the number. The load term therefore DEFAULTS OFF in
# capacity_gate() (CC_FIRE_LOAD_TERM) and has been off on the Agent-tool path since Wave D;
# `segments` and `active` carry its intent because they DO move with the spawn. The literal stays at
# 2.0 on purpose — C18: a fix moves a TERM SWITCH, never a ceiling — and raising it is the lazy
# design docs/plans/LOAD_INSENSITIVE_VERIFY_V2.md:156 exists to reject. It still binds only where
# `cc_capacity_admit` leaves the term on: the two unattended recovery callers
# (scripts/boot-resume-launch.sh, scripts/limit-recover/lr-fire-resume.sh), DELIBERATELY — see the
# load-term block below, which prices that imprecision at a delayed resume, and both are
# budget-released after CC_ADMIT_BUDGET consecutive refusals.
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

# ── AN INTEGER'S CHARSET IS NOT ITS RANGE (W2FA A2, 2026-09-20) ────────────────────────────────
# `cc_hw_is_int` asks "is every character a digit", which is all a sysctl reading ever needed. It is
# NOT enough for a value that becomes an OPERAND of `[ -gt ]` or `$(( ))`, and W2FA's own TTL
# resolver inherited that gap one layer in. MEASURED 2026-09-20 — three readings of one unvalidated
# value, in both failure directions and once fatally:
#   · 21 DIGITS. CC_ADMIT_TOKEN_TTL_S=999999999999999999999 passes cc_hw_is_int, so the hardened
#     resolver accepts it, and `[ "$age" -gt "$ttl" ]` then ERRORS rc 2 (`[: …: integer expected`
#     on stderr) which `if` reads identically to a clean false. A 315,360,000 s token ADMITTED,
#     rc 0, basis=token. The exact fail-open D2 closed — the resolver was hardened, the RANGE was
#     not (docs/lessons/predicate-error-exit-is-indistinguishable-from-false.md).
#   · OVERFLOW. A 20-digit stage wraps in `$(( ))`: CC_RECYCLE_DRAFT_WAIT=99999999999999999999
#     yields TTL 7766279631452242759, and the int64 maximum yields TTL -9223372036854774969 — a
#     NEGATIVE bound, under which EVERY token is instantly expired. One operand, an admit-everything
#     and a refuse-everything failure a digit apart.
#   · OCTAL. A leading zero re-reads the same digits: `$(( 0600 ))` is 384, so
#     CC_RECYCLE_DRAFT_WAIT=0600 gives TTL 1224 instead of 1440 — silently 216 s short — and `0900`
#     is not a valid octal literal at all, so bash aborts the arithmetic ("value too great for
#     base") and, under a caller's `set -e` (lr-fire-resume sources this file), kills the process.
# So an operand is validated on THREE properties and NORMALISED, never on charset alone. Ten digits
# is 317 years in seconds — past any bound this file could want — and four of them summed stay four
# orders of magnitude inside int64, so the derived sum cannot wrap either.
CC_HW_INT_MAX_DIGITS=10
CC_HW_INT_VALUE=""
cc_hw_is_int_operand() { # $1 → 0 usable in `[ -gt ]` AND `$(( ))` · sets CC_HW_INT_VALUE (normalised)
  local v="${1:-}"
  CC_HW_INT_VALUE=""
  cc_hw_is_int "$v" || return 1
  v="${v#"${v%%[!0]*}"}"                     # the leading-zero RUN is what makes $(( )) read octal
  [ -n "$v" ] || v=0                         # …and an all-zero value strips to nothing, not to 0
  [ "${#v}" -le "$CC_HW_INT_MAX_DIGITS" ] || return 1
  CC_HW_INT_VALUE="$v"
  return 0
}

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
# THE BOUND'S OWN OPERANDS ARE RANGE-CHECKED (W2FA A2, third site, 2026-09-20). MEASURED
# 2026-09-20: with CC_ADMIT_BUDGET=999999999999999999999 — all digits, so the charset test passed —
# `[ "$n" -gt "$budget" ]` ERRORS rc 2 (`[: …: integer expected`) and `if` reads it as a clean
# false, so the counter climbs forever and the release NEVER fires. Eight consecutive refusals, no
# release, against a control at budget 3 that released on the fourth. That is §9's law — "no gate
# on an actuation path may be unbounded" — defeated by a typo, and case 4 of this suite calls that
# law the central property under test. The state file's own counter is bounded for the same reason:
# a 21-digit value there wraps `$((n + 1))`. Rejecting either is rc 1, i.e. UNTRACKABLE ⇒ the caller
# must ADMIT, which is the direction that keeps the gate bounded — unchanged, and the safe one.
cc_hw_budget_charge() { # $1=state-file (may be empty) $2=budget → 0 charged / 10 released / 1 untrackable
  local sf="${1:-}" budget="${2:-}" n
  [ -n "$sf" ] || return 1
  cc_hw_is_int_operand "$budget" || return 1
  budget="$CC_HW_INT_VALUE"
  n="$(cat "$sf" 2>/dev/null || echo 0)"
  cc_hw_is_int_operand "$n" || CC_HW_INT_VALUE=0
  n=$(( CC_HW_INT_VALUE + 1 ))
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
         --arg bld "${CC_ADMIT_BLIND:-}" --arg tok "${CC_ADMIT_TOKEN_NOTE:-}" \
    '{ts:$ts,hook:"capacity-admit",sid:$sid,disposition:$disp,reason:"capacity",
      gate:"capacity-admit",verdict:$v,basis:$b,caller:$c,what:$w,detail:$d}
     + (if $t    == "" then {} else {term:$t} end)
     + (if $pres == "" then {} else {presence:$pres} end)
     + (if $rsv  == "" then {} else {reserve:$rsv} end)
     + (if $tms  == "" then {} else {terms:$tms} end)
     + (if $bld  == "" then {} else {blind:$bld} end)
     + (if $tok  == "" then {} else {token:$tok} end)' >> "$idl" 2>/dev/null || true
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
# PER-RUN KEYING (LIMIT_RECOVER_100P W2, 2026-09-19). The key was the CALLER ALONE, so the whole
# box shared five counters and every concurrent recovery charged the same one. Measured 2026-09-19
# (U05 §3.4): five in-place recoveries ran through `lr-fire-resume.refusals`; the ONE that survived
# the gate did so because two EARLIER, unrelated invocations had pre-spent two thirds of the budget,
# and its release then RESET the counter — so the next four started at "refusal 1 of 3" and could
# never reach the release inside their watcher's window. One recovery's refusals released another
# recovery's spawn, and one recovery's admit disarmed the next one's bound.
#
# CC_ADMIT_BUDGET_KEY is the run id. Unset ⇒ the path is byte-identical to what it has always been,
# so no existing caller changes behaviour. The budget VALUE is deliberately untouched (U05 P3 asked
# for 1 here; D3-safety R2 refuted it — budget 1 makes every remaining term a one-attempt delay plus
# a page). An unusable key degrades to the caller-only file rather than to no file at all: an
# untrackable bound is an UNBOUNDED gate (see _cc_admit_spend), which is the failure this must not
# manufacture out of a bad key.
_cc_admit_state_file() { # $1=caller → path, or empty when the caller id is unusable
  local dir="${CC_ADMIT_STATE_DIR:-$HOME/.claude/autonomy/capacity-admit}" key="${CC_ADMIT_BUDGET_KEY:-}"
  case "$1" in ''|*[!A-Za-z0-9._-]*) return 0 ;; esac
  case "$key" in *[!A-Za-z0-9._-]*) key="" ;; esac
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s/%s%s.refusals' "$dir" "$1" "${key:+.$key}"
}

_cc_admit_reset() { local f; [ "${_CC_ADMIT_PROBE:-0}" = 1 ] && return 0; f="$(_cc_admit_state_file "$1")"; [ -n "$f" ] && : > "$f" 2>/dev/null; return 0; }

# ══ THE ADMISSION TOKEN (LIMIT_RECOVER_100P W2, 2026-09-19) ═════════════════════════════════════
# ONE net-zero operation was being gated TWICE, 11-16 s apart, by two processes that could not see
# each other. handoff-fire.sh:8270 does not gate a RECYCLE at all — ":5620 a recycle REPLACES a
# session (net-zero panes), so gating it would strand the very handoff that SHEDS load" — and the
# in-place limit recovery IS that recycle. But the relaunch it types is `bash <launcher>`, a FRESH
# process tree in the pane's own shell, and that tree re-evaluates the gate from scratch. Measured
# 2026-09-19 (U05 §3.3): the fleet probe ADMITTED five times and the launcher REFUSED 11-16 s later
# every time, after the transplant had already run. Four husks.
#
# The token makes the probe's decision THE decision, without letting a probe WIDEN admission:
#   · minted only by a caller whose probe ADMITTED (the mint is a separate verb; the gate never
#     mints, so a refusal can never leave a token behind),
#   · ONE-SHOT — unlinked on read, whatever the verdict, so it grants at most one spawn,
#   · TTL-bounded, and the bound is DERIVED from the stages the token must cross rather than
#     guessed (see _cc_admit_token_ttl; CC_ADMIT_TOKEN_TTL_S still overrides outright),
#   · uid-checked (`-O`) — another uid's file is never honoured,
#   · SID-ENFORCED — a token names the session it was issued for and cannot be replayed onto a
#     different spawn (D3-safety R13),
#   · PROBE-INERT — cc_capacity_probe never redeems, or the token would turn the probe's
#     never-spend contract into a spend (U05 T1's 15c is the case that keeps this honest).
#
# IT CANNOT ADMIT ANYTHING THE GATE DID NOT ALREADY ADMIT for that sid ≤ TTL ago. And no outcome
# here is ever a SILENT one: the reason rides on that row's `token` field (CC_ADMIT_TOKEN_NOTE)
# whichever way the evaluation goes.
#
# ── THE TWO OUTCOMES BELOW AN ADMIT, AND WHY THEY DIFFER (W2FA D5, 2026-09-20) ──────────────
# A token that is missing, a symlink, another uid's, unenforceable or FOREIGN falls through to a
# fresh evaluation, because no first gate was ever found FOR THIS SPAWN — there is no decision to
# contradict, and refusing would convict a caller that merely named a path.
#
# A token this library has POSITIVELY IDENTIFIED as this spawn's own (well-formed, our uid, our
# sid) and then cannot use — expired, or lost to a concurrent claim — is the opposite case, and
# falling through there is the defect itself: a fresh evaluation in the pane IS the second gate, in
# the second process, after the transplant. So that is a NAMED TERMINAL STATE (`token-stale`, rc 9,
# term `token`), not a re-decision. CC_ADMIT_TOKEN_REQUIRED=off restores the old fall-through.
CC_ADMIT_TOKEN_AGE=""
CC_ADMIT_TOKEN_SID=""
CC_ADMIT_TOKEN_TERMS=""
CC_ADMIT_TOKEN_NOTE=""
CC_ADMIT_TOKEN_UNLINK=""
# Set by _cc_admit_token_redeem the moment the record is identified as THIS spawn's own admission.
# Past that point a non-redemption may not fall through — see the header's two-outcomes block.
CC_ADMIT_TOKEN_TERMINAL=""
# The record's own identity (`<sid>.<issued>`) and how many times THIS record has reached the
# terminal state. Both exist for one reason: the terminal state can REPEAT (W2FA A1 below).
CC_ADMIT_TOKEN_IDENT=""
CC_ADMIT_TOKEN_REPEAT=""
cc_capacity_token_note() { printf '%s' "$CC_ADMIT_TOKEN_NOTE"; }
# The terminal state's occurrence number, for a caller that prints operator-facing advice: the
# advice for occurrence 1 ("re-fire") and for occurrence N ("re-running cannot help") differ, and a
# caller reaching into a global to learn that would be the coupling cc_capacity_token_note avoids.
cc_capacity_token_repeat() { printf '%s' "$CC_ADMIT_TOKEN_REPEAT"; }

# ── THE ABANDONED CLAIM COPY (W2FA A5, 2026-09-20) ─────────────────────────────────────────────
# The atomic claim renames the token to `<token>.claim.<pid>.<nonce>` and discards it a few
# statements later. A process that dies in between — the pane's shell killed, the box rebooted, an
# `rm` that silently no-ops (15k's premise: an unwritable directory, an immutable flag, a full
# inode table) — leaves that copy behind forever, at 0600, in the directory the driver reads.
# OBSERVED. It is not a replay risk, because rename(2) has already made the ORIGINAL name (the one
# CC_ADMIT_TOKEN points at) unreachable; it is litter that accumulates one file per crashed
# recovery, and litter in an admission store is what makes the next reader distrust the store.
#
# THE MINT SWEEPS, NEVER THE REDEEMER. The mint is the DRIVER — once per recovery, in the process
# that owns the directory — while the redeemer runs in the pane, under the token's own TTL, beside
# concurrent siblings. AGE-BOUNDED AT THE TTL, and that bound is load-bearing rather than tidy: a
# LIVE claim exists for the few statements between rename and discard, so a sweep without the bound
# could delete a concurrent redeemer's claim and re-open the very hole D1 closed. Own-uid only,
# regular files only, and a `for` glob rather than `find` — BSD find does not walk a symlinked start
# dir without -H, and $BATS_TEST_TMPDIR is one on this box, where its null would read as "nothing
# to sweep" (memory `symlinked-store-invisible-to-find`).
_cc_admit_mtime() { # $1=path → epoch seconds on stdout, or nothing
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || printf ''
}
_cc_admit_token_sweep() { # $1=dir → always 0 · prints how many abandoned claims were removed
  local d="${1:-}" f now mt n=0
  [ -d "$d" ] || { printf '0'; return 0; }
  now="$(date +%s 2>/dev/null || printf '')"
  cc_hw_is_int_operand "$now" || { printf '0'; return 0; }
  now="$CC_HW_INT_VALUE"
  _cc_admit_token_ttl
  for f in "$d"/*.claim.*; do
    [ -f "$f" ] || continue                  # an unmatched glob stays literal; this also skips dirs
    [ ! -L "$f" ] || continue                # `[ ! -L ]`, never `[ -L ] && continue`: a false && list
                                             # is rc 1, which errexit kills mid-loop
    [ -O "$f" ] || continue
    mt="$(_cc_admit_mtime "$f")"
    cc_hw_is_int_operand "$mt" || continue
    [ $(( now - CC_HW_INT_VALUE )) -gt "$CC_ADMIT_TOKEN_TTL_VALUE" ] || continue
    rm -f "$f" 2>/dev/null || true
    [ -e "$f" ] || n=$(( n + 1 ))            # counted from a re-read, never from rm's own rc (D3)
  done
  printf '%s' "$n"
  return 0
}

cc_capacity_token_mint() { # $1=sid [$2=explicit path] → prints the token path · rc 1 = not minted
  local sid="${1:-}" path="${2:-}" dir uid
  case "$sid" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  uid="$(id -u 2>/dev/null || printf '?')"
  if [ -n "$path" ]; then
    dir="$(dirname "$path")"
    mkdir -p "$dir" 2>/dev/null || return 1
    : > "$path" 2>/dev/null || return 1
    chmod 600 "$path" 2>/dev/null || true
    _cc_admit_token_sweep "$dir" >/dev/null
  else
    # The NONCE comes from mktemp, which creates the file atomically at mode 0600 — so two
    # concurrent recoveries of the same sid cannot collide on a name, and there is no window in
    # which the path exists world-readable. `<sid>.<nonce>` keeps the sid in the path: a token
    # found on disk names its own subject without being parsed.
    dir="${CC_ADMIT_STATE_DIR:-$HOME/.claude/autonomy/capacity-admit}/tokens"
    mkdir -p "$dir" 2>/dev/null || return 1
    path="$(mktemp "$dir/$sid.XXXXXXXX" 2>/dev/null)" || return 1
    chmod 600 "$path" 2>/dev/null || true
    _cc_admit_token_sweep "$dir" >/dev/null
  fi
  # ONE line, tab-separated: issued · sid · uid · the TERM SWITCHES the minting evaluation ran with.
  # The terms are recorded because the T3 ratchet is about the pair agreeing: a token minted under a
  # different term set than the launcher would evaluate is still ONE decision, and the row must be
  # able to say which decision it was.
  printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$sid" "$uid" "${CC_ADMIT_TERMS:-}" > "$path" 2>/dev/null || return 1
  printf '%s' "$path"
}

# ── THE RECORD IS A SHAPE, NOT A STRING (W2FA D4, 2026-09-20) ──────────────────────────────────
# The record used to be pulled apart with `cut -f1/-f2/-f4`, and `cut` WITHOUT `-s` prints the WHOLE
# LINE when the delimiter is absent. MEASURED: a file containing only `date +%s` redeemed — rc 0,
# "issued for 1789862813", file consumed — because the sid field equalled the timestamp, so naming
# that number as the wanted sid made any such file an admission. The mint writes exactly four
# TAB-separated fields; nothing checked that, so the shape carried no information at all.
#
# ONE awk pass yields NF AND the fields, so the count and the values cannot disagree, and the loop
# below reads them through a heredoc rather than a pipe — a `while read` on the right of a pipe runs
# in a subshell and its assignments never escape it.
_CC_ADMIT_TOK_NF=0
_CC_ADMIT_TOK_ISSUED=""
_CC_ADMIT_TOK_SID=""
_CC_ADMIT_TOK_UID=""
_CC_ADMIT_TOK_TERMS=""
_CC_ADMIT_TOK_BAD=""
_cc_admit_token_parse() { # $1=path → 0 first line read (fields set) / 1 unreadable
  local rec line i=0
  _CC_ADMIT_TOK_NF=0; _CC_ADMIT_TOK_ISSUED=""; _CC_ADMIT_TOK_SID=""; _CC_ADMIT_TOK_UID=""; _CC_ADMIT_TOK_TERMS=""
  rec="$(awk -F'\t' 'NR==1{printf "%s\n%s\n%s\n%s\n%s\n", NF, $1, $2, $3, $4; exit}' "$1" 2>/dev/null)" || return 1
  [ -n "$rec" ] || return 1
  while IFS= read -r line; do
    case "$i" in
      0) _CC_ADMIT_TOK_NF="$line" ;;
      1) _CC_ADMIT_TOK_ISSUED="$line" ;;
      2) _CC_ADMIT_TOK_SID="$line" ;;
      3) _CC_ADMIT_TOK_UID="$line" ;;
      4) _CC_ADMIT_TOK_TERMS="$line" ;;
    esac
    i=$(( i + 1 ))
  done <<TOKREC
$rec
TOKREC
  return 0
}

# THE DISCARD IS VERIFIED, NEVER ASSUMED (W2FA D3). `rm -f … || true` throws away the one result
# that decides whether a token is one-shot; the `|| true` here is safe ONLY because the `-e` test
# after it — a DIFFERENT call, not this one's exit code — is what renders the verdict. The rename
# has already made the ORIGINAL name unreachable, so a surviving claim copy is hygiene rather than a
# replay; it is still a FACT, and the row says so instead of asserting a removal that did not happen.
_cc_admit_token_discard() { # $1=claim path → always 0 · sets CC_ADMIT_TOKEN_UNLINK if it survives
  CC_ADMIT_TOKEN_UNLINK=""
  rm -f "$1" 2>/dev/null || true
  if [ -e "$1" ]; then CC_ADMIT_TOKEN_UNLINK="the one-shot copy was NOT removed ($1)"; fi
  return 0
}

# ── THE TERMINAL STATE IS BOUNDED, AND A REPEAT SAYS SO (W2FA A1, 2026-09-20) ──────────────────
# MEASURED 2026-09-20 on a QUIET, HEALTHY box (load override 0.01/core, i.e. a box a fresh
# evaluation would ADMIT): a token whose directory is chmod 555 can be neither claimed nor
# unlinked, so it stays on disk, and TEN redemptions produced ten rc-9 refusals and TEN
# BYTE-IDENTICAL PAGES. The rename claim is the ONLY terminal path that leaves the record behind —
# the post-claim, clock and expiry paths all discard it first, so they cannot repeat — and nothing
# bounded it. A recovery path that pages without bound is worse than the replay it replaced.
#
# This is alarm polarity (memory `alarm-polarity-and-attention-budget`): an alarm that ALWAYS fires
# carries as little as one that cannot. §9's law asks that a standing state be converted into an
# EVENT, and ten identical pages are a standing state wearing an event's clothes.
#
# So the OCCURRENCE is counted, per RECORD — `<sid>.<issued>`, both fields already validated by
# _cc_admit_token_shape before this can be reached (charset, and an operand-bounded epoch), so
# neither can shape a path:
#   · the FIRST occurrence pages, exactly as before,
#   · every later one carries `REPEAT #N` on the reason and on the row, and does NOT page,
#   · the REFUSAL is unchanged at every occurrence. Bounding an ALARM must never widen ADMISSION,
#     and that trade is not taken here: rc 9 is returned identically at occurrence 1 and 100.
# CC_ADMIT_TOKEN_TERMINAL_PAGES (default 1) is the bound; 0 silences the page outright.
#
# RESIDUAL, named rather than hidden: when the STATE dir is itself unwritable the counter cannot be
# kept and the occurrence reads 1 every time — i.e. it degrades to exactly today's behaviour,
# paging, and the row says `occurrence 1` while the note says the count is untrackable. For an
# alarm that is the correct direction (an untrackable bound must not silently SUPPRESS), and it is
# the mirror of the argument cc_hw_budget_charge makes for admitting on an untrackable bound.
CC_ADMIT_TOKEN_OCC_NOTE=""
_cc_admit_token_occurrence() { # $1=ident → prints the occurrence number (>=1) · always 0
  local dir f n
  CC_ADMIT_TOKEN_OCC_NOTE=""
  case "${1:-}" in
    ''|*[!A-Za-z0-9._-]*)
      CC_ADMIT_TOKEN_OCC_NOTE="the record has no usable identity, so repeats cannot be counted"
      printf '1'; return 0 ;;
  esac
  dir="${CC_ADMIT_STATE_DIR:-$HOME/.claude/autonomy/capacity-admit}/terminal"
  if ! mkdir -p "$dir" 2>/dev/null; then
    CC_ADMIT_TOKEN_OCC_NOTE="the state dir is unwritable, so repeats cannot be counted"
    printf '1'; return 0
  fi
  f="$dir/$1.terminal"
  n="$(cat "$f" 2>/dev/null || printf '0')"
  cc_hw_is_int_operand "$n" || CC_HW_INT_VALUE=0
  n=$(( CC_HW_INT_VALUE + 1 ))
  if ! printf '%s\n' "$n" > "$f" 2>/dev/null; then
    CC_ADMIT_TOKEN_OCC_NOTE="the occurrence counter could not be written, so repeats cannot be counted"
    printf '1'; return 0
  fi
  printf '%s' "$n"
  return 0
}

# Every property a redeemable record must have, in ONE predicate so the pre-claim gate and the
# post-claim authoritative re-read cannot drift apart. The reason rides on _CC_ADMIT_TOK_BAD.
_cc_admit_token_shape() { # $1=path $2=wanted sid $3=this uid → 0 well-formed AND ours / 1 not
  _CC_ADMIT_TOK_BAD=""
  if ! _cc_admit_token_parse "$1"; then
    _CC_ADMIT_TOK_BAD="UNREADABLE — no first line"; return 1
  fi
  if [ "$_CC_ADMIT_TOK_NF" != 4 ]; then
    _CC_ADMIT_TOK_BAD="MALFORMED — a token is a 4-field TAB record (issued/sid/uid/terms); this line has ${_CC_ADMIT_TOK_NF}"
    return 1
  fi
  case "$_CC_ADMIT_TOK_SID" in
    ''|*[!A-Za-z0-9._-]*)
      _CC_ADMIT_TOK_BAD="MALFORMED — sid field '${_CC_ADMIT_TOK_SID}' is not a usable session id"; return 1 ;;
  esac
  # THE OTHER OPERAND OF THE SAME SUBTRACTION (W2FA A2). `age=$(( now - issued ))` reads this field,
  # so charset alone is not enough here either: a 21-digit epoch wraps, and a decimal one aborts the
  # arithmetic outright — leaving `age` EMPTY, which makes both expiry comparisons exit rc 2 and the
  # token immortal. Same operand test, same normalisation.
  if ! cc_hw_is_int_operand "$_CC_ADMIT_TOK_ISSUED"; then
    _CC_ADMIT_TOK_BAD="MALFORMED — issued field '${_CC_ADMIT_TOK_ISSUED}' is not an epoch integer this shell can subtract"; return 1
  fi
  if [ "$_CC_ADMIT_TOK_UID" != "$3" ]; then
    _CC_ADMIT_TOK_BAD="MALFORMED — the record was minted by uid '${_CC_ADMIT_TOK_UID}', this process is uid '$3'"
    return 1
  fi
  if [ "$_CC_ADMIT_TOK_SID" != "$2" ]; then
    _CC_ADMIT_TOK_BAD="FOREIGN — issued for '${_CC_ADMIT_TOK_SID}' but this spawn is '$2'"; return 1
  fi
  return 0
}

# ── THE TTL, RESOLVED ONCE AND ALWAYS AN INTEGER (W2FA D2, 2026-09-20) ─────────────────────────
# The expiry test used to read the env var directly: `[ "$age" -gt "${CC_ADMIT_TOKEN_TTL_S:-300}" ]`.
# With a non-integer value (`300s`) `[` does not return false, it ERRORS with rc 2 — and `if` reads
# rc 2 identically to a clean false. MEASURED 2026-09-20: bash printed `[: 300s: integer expected`
# to stderr and the gate returned rc 0, ADMITTING a token 315,360,000 s old on a box at 9.90/core.
# The TTL is the only thing bounding the stale-admission window and its guard failed OPEN — the
# class in docs/lessons/predicate-error-exit-is-indistinguishable-from-false.md.
#
# SETS GLOBALS, NEVER PRINTS INTO `$( )`. A resolver called as `x="$(f)"` runs in a subshell, so any
# note it sets about WHY it fell back is discarded with that subshell (memory
# `assignment-inside-command-substitution-never-escapes`) — and a fallback nobody can see is how a
# bad TTL stays invisible in the first place.
#
# ── AND IT IS SIZED FROM THE STAGES IT MUST CROSS (W2FA D5, 2026-09-20) ────────────────────────
# The flat 300 s was SHORTER THAN ONE of those stages. MEASURED 2026-09-20: a token minted before
# the transplant is already stale when the launcher redeems it, is silently consumed, and the gate
# falls through to a FRESH in-pane evaluation returning rc 9 — i.e. under exactly the loaded
# conditions that produce limits, the fall-through re-created the two-gate split this token exists
# to close, after the transplant had already run.
#
# The window, read off the one rail that crosses it (lr-handoff.sh:616 mints, lr-fire-resume.sh:381
# redeems, and everything between is handoff-fire --recycle):
#
#   the transplant, then handoff-fire's preamble    NO named constant bounds either
#   composer gate                                   CC_RECYCLE_DRAFT_WAIT      180 s
#   /exit, then the ps-poll for a shell             HF_RECYCLE_SHELL_WAIT_S    600 s
#   ── the launcher is typed HERE; this is where the token is redeemed ──
#   boot + engagement                               after the redemption — not crossed
#
# READ BY NAME WHERE A CALLER SUPPLIES THEM — AND IN PRODUCTION NOBODY DOES (corrected W2FA A3,
# 2026-09-20). The original claim here was "READ BY NAME, NEVER RE-TYPED", and it is false in the
# environment this library actually runs in. The four names are handoff-fire.sh's OWN locals,
# expanded there as `${NAME:-<literal>}` and EXPORTED BY NOTHING in the tree — zero `export` of any
# of them in handoff-fire.sh, in scripts/limit-recover/ or in bin/. MEASURED under `env -i`, which
# is the floor of what a launcher heredoc and a launchd job provide: every read misses and the
# value is the sum of THIS FILE'S OWN LITERALS, 180+600+180+60 = 1020 s. The SIZE is right; the
# mechanism was not, and the case that appeared to prove it (15s) EXPORTS the names itself — a
# fixture manufacturing the very environment production lacks.
#
# The reads STAY, because as an OVERRIDE they are honest and free: a caller that does parameterise
# a stage gets a TTL that follows it. What replaces the false claim is a TRIPWIRE rather than a
# hope — coverage case 31 reads handoff-fire.sh's own `:-<literal>` defaults and goes RED when they
# move away from the literals below, and case 15ac pins the `env -i` value at 1020 so a literal
# here cannot move alone either. RCY_BOOT_STALE_S is borrowed as the allowance for the two
# UNBOUNDED stages above: it is handoff-fire's own number for the longest a recycle phase may take,
# so this expression has no magnitude of its own except the slack.
#
# TWO-SIDED, which is what makes the size non-arbitrary rather than merely bigger:
#   ≥ the stages it must cross (780 s), or a token cannot survive its own operation;
#   ≤ handoff-fire's whole-recycle bound (1200 s), or a token outlives the recycle that minted it.
# The derived default lands at 1020 s, inside both. CC_ADMIT_TOKEN_TTL_S still overrides outright.
CC_ADMIT_TOKEN_TTL_VALUE=""
CC_ADMIT_TOKEN_TTL_NOTE=""
_cc_admit_token_stage() { # $1=env value $2=fallback → always 0 · prints an integer, never empty
  # if/else, never `cc_hw_is_int "$1" && printf …`: an && list whose left side is false makes the
  # whole statement rc 1, which is fatal under a caller's `set -e` (lr-fire-resume sources this).
  # The value printed is the NORMALISED one, and the test is the OPERAND test: a stage goes straight
  # into `$(( ))`, where an in-charset value can still overflow or be re-read as octal (W2FA A2).
  if cc_hw_is_int_operand "$1"; then printf '%s' "$CC_HW_INT_VALUE"; else printf '%s' "$2"; fi
  return 0
}
_cc_admit_token_ttl() { # → always 0 · sets CC_ADMIT_TOKEN_TTL_VALUE (an integer) + _NOTE
  local t="${CC_ADMIT_TOKEN_TTL_S:-}" draft shell boot slack
  CC_ADMIT_TOKEN_TTL_NOTE=""
  # Recomputed EVERY call, never cached: a stage constant that moves must move this with it, and a
  # value resolved once at source time would freeze whichever environment happened to load us.
  draft="$(_cc_admit_token_stage "${CC_RECYCLE_DRAFT_WAIT:-}" 180)"
  shell="$(_cc_admit_token_stage "${HF_RECYCLE_SHELL_WAIT_S:-}" 600)"
  boot="$(_cc_admit_token_stage "${RCY_BOOT_STALE_S:-}" 180)"
  slack="$(_cc_admit_token_stage "${CC_ADMIT_TOKEN_TTL_SLACK_S:-}" 60)"
  CC_ADMIT_TOKEN_TTL_VALUE=$(( draft + shell + boot + slack ))
  [ -n "$t" ] || return 0
  if cc_hw_is_int_operand "$t"; then CC_ADMIT_TOKEN_TTL_VALUE="$CC_HW_INT_VALUE"; return 0; fi
  CC_ADMIT_TOKEN_TTL_NOTE="CC_ADMIT_TOKEN_TTL_S='${t}' is not an integer this shell can compare (charset, magnitude, or a leading zero) — bounded at ${CC_ADMIT_TOKEN_TTL_VALUE}s instead"
  return 0
}

_cc_admit_token_redeem() { # → 0 redeemed (the caller must ADMIT) / 1 no usable token · sets the CC_ADMIT_TOKEN_* globals
  CC_ADMIT_TOKEN_AGE=""; CC_ADMIT_TOKEN_SID=""; CC_ADMIT_TOKEN_TERMS=""; CC_ADMIT_TOKEN_NOTE=""; CC_ADMIT_TOKEN_UNLINK=""
  CC_ADMIT_TOKEN_TERMINAL=""; CC_ADMIT_TOKEN_IDENT=""; CC_ADMIT_TOKEN_REPEAT=""
  # Resolved HERE rather than beside the expiry test, so every note and every row this evaluation
  # writes names the TTL that was actually in force — including the ones that return long before
  # the age is computed.
  _cc_admit_token_ttl
  # CC_ADMIT_TOKEN is the library's own spelling; LR_ADMIT_TOKEN is the limit-recover launcher's,
  # accepted here so a launcher env that carries only the LR_ name still redeems. Both are read,
  # neither is exported by this library, and lr-fire-resume passes CC_ADMIT_TOKEN call-scoped.
  local t="${CC_ADMIT_TOKEN:-${LR_ADMIT_TOKEN:-}}" want="${CC_ADMIT_WANT_SID:-}" issued sid terms now age claim ttl me
  me="$(id -u 2>/dev/null || printf '?')"
  [ -n "$t" ] || return 1
  # A TOKEN IS AN ADMISSION, NEVER A REDIRECTION TO ONE (W2FA D3). `-f`, `-O` and `rm` ALL follow a
  # symlink, so a link's target was validated, never consumed, and survived — measured on the
  # pre-W2FA library as three rc-0 redemptions of one record, each row reading basis=token/admit.
  # `-L` is tested FIRST because every check after it answers a question about the TARGET while the
  # caller named the LINK, and the two are only the same file until someone makes them differ.
  if [ -L "$t" ]; then
    CC_ADMIT_TOKEN_NOTE="token is a SYMLINK ($t) — refused and NOT consumed: -f/-O/rm all follow the link, so its target would be validated and never spent"
    return 1
  fi
  if [ ! -f "$t" ]; then CC_ADMIT_TOKEN_NOTE="token ABSENT ($t) — evaluating fresh"; return 1; fi
  if [ ! -O "$t" ]; then CC_ADMIT_TOKEN_NOTE="token not owned by uid ${me} ($t) — refused, not consumed, evaluating fresh"; return 1; fi
  # SID ENFORCEMENT IS THE LIBRARY'S PROPERTY, NOT THE CALLER'S CONVENTION (W2FA D4). The old test
  # was `[ -n "$want" ] && [ "$sid" != "$want" ]`, i.e. SKIPPED ENTIRELY when the caller set no sid
  # — and MEASURED, a token minted for sid-AAA then admitted a completely unrelated caller, rc 0,
  # detail "issued for sid-AAA". The caller that forgets to name its session is precisely the caller
  # that needed the check, so an unenforceable token is not an admission at all.
  if [ -z "$want" ]; then
    CC_ADMIT_TOKEN_NOTE="token NOT REDEEMED — sid enforcement unavailable (CC_ADMIT_WANT_SID is empty); a token that cannot be bound to a session is not an admission. Refused, NOT consumed"
    return 1
  fi
  # EVERY PRE-CLAIM REFUSAL LEAVES THE FILE ALONE. We only consume a file we have positively
  # identified as OUR token: a foreign one is a sibling recovery's admission (destroying it turns
  # one wiring bug into two failures), and an unidentified one is just a path the caller named —
  # deleting that would make CC_ADMIT_TOKEN a remove-anything primitive.
  if ! _cc_admit_token_shape "$t" "$want" "$me"; then
    CC_ADMIT_TOKEN_NOTE="token REFUSED: ${_CC_ADMIT_TOK_BAD} — not consumed, evaluating fresh"
    return 1
  fi
  # ── PAST THIS LINE A FALL-THROUGH IS THE DEFECT (W2FA D5) ────────────────────────────────────
  # The record is now positively identified as THIS spawn's own admission: 4-field, our uid, our
  # sid. Every refusal from here on is therefore about an admission we HAVE and cannot use, and a
  # fresh evaluation over one of those is the second gate on one operation — the split. The flag is
  # the library's way of saying that to cc_capacity_admit, which owns the verdict.
  CC_ADMIT_TOKEN_TERMINAL=1
  # The record's identity, captured HERE and not later: the post-claim re-read overwrites every
  # _CC_ADMIT_TOK_* field, and one terminal path (a failed claim) never reaches that re-read at all.
  # Both halves were validated two lines above, so neither can shape the counter's path.
  CC_ADMIT_TOKEN_IDENT="${_CC_ADMIT_TOK_SID}.${_CC_ADMIT_TOK_ISSUED}"
  # ── THE ONE-SHOT, MADE ATOMIC (W2FA D1, 2026-09-20) ──────────────────────────────────────────
  # This WAS `rm -f "$t" || true`, placed AFTER the awk read. Read-then-unlink is not one-shot: two
  # processes redeeming the same token path with the same CC_ADMIT_WANT_SID on a refusing box (load
  # override 99 on 10 cores) BOTH returned rc 0 in 40 of 40 trials, because both completed their
  # read before either unlinked. One probe admission then grants as many spawns as there are
  # concurrent readers — the exact regime this wave exists for (five concurrent recoveries on
  # 2026-09-19), and handoff-fire's boot arm plus its watcher can hold the same launcher, hence the
  # same token path, twice.
  #
  # rename(2) IS the atomic claim: of N concurrent redeemers exactly one `mv` succeeds and the rest
  # get ENOENT, so the winner is decided by the kernel rather than by who finishes an awk first. The
  # claim name lives in the token's OWN directory, never /tmp, so the rename cannot degrade into a
  # cross-device copy+unlink (which is not atomic and would re-open this hole). A FAILED claim is
  # never a silent fall-through to a fresh evaluation: a redeemer that cannot prove exclusivity has
  # no admission to carry, and says so.
  claim="$t.claim.$$.${RANDOM:-0}"
  if ! mv "$t" "$claim" 2>/dev/null; then
    CC_ADMIT_TOKEN_NOTE="token NOT CLAIMED ($t) — the atomic rename failed: a concurrent redeemer took it, or its directory is not writable. One-shot cannot be enforced, so this is not an admission"
    return 1
  fi
  # AUTHORITATIVE RE-READ, ON OUR OWN COPY, AND BEFORE THE DISCARD. The pre-claim read decided only
  # whether the file was ours to take; between that read and the rename anything could have
  # rewritten it. Past the claim no other process can reach this inode, so these are the values the
  # admission is granted on — and they must be read while the copy still exists, which is the one
  # ordering constraint the discard imposes.
  if ! _cc_admit_token_shape "$claim" "$want" "$me"; then
    _cc_admit_token_discard "$claim"
    CC_ADMIT_TOKEN_NOTE="token REFUSED after the claim: ${_CC_ADMIT_TOK_BAD} — consumed${CC_ADMIT_TOKEN_UNLINK:+ [${CC_ADMIT_TOKEN_UNLINK}]}"
    return 1
  fi
  issued="$_CC_ADMIT_TOK_ISSUED"; sid="$_CC_ADMIT_TOK_SID"; terms="$_CC_ADMIT_TOK_TERMS"
  _cc_admit_token_discard "$claim"
  # THE CLOCK IS AN INPUT AND IS VALIDATED LIKE ONE. An unreadable `date` leaves `now` empty, which
  # makes the arithmetic below error and every comparison after it meaningless — the same fail-open
  # shape as the TTL, arriving from the other operand.
  now="$(date +%s 2>/dev/null || printf '')"
  # THE OPERAND TEST, not the charset one (W2FA A2/A4): `now` is the left operand of the same
  # subtraction as `issued`, so a 21-digit clock wraps it exactly as a 21-digit epoch does.
  if ! cc_hw_is_int_operand "$now"; then
    CC_ADMIT_TOKEN_NOTE="token NOT REDEEMED — the clock is unreadable (date +%s gave '${now}'), so age is unmeasurable; consumed, evaluating fresh${CC_ADMIT_TOKEN_UNLINK:+ [${CC_ADMIT_TOKEN_UNLINK}]}"
    return 1
  fi
  ttl="$CC_ADMIT_TOKEN_TTL_VALUE"
  age=$(( now - issued ))
  # A NEGATIVE AGE IS ITS OWN STATE, NOT AN EXPIRY (W2FA A4). Both are terminal and both consume,
  # but a record issued AHEAD of this clock is a skew or a forgery, and reporting it as
  # "EXPIRED (-100000s old > TTL 1020s)" is a diagnosis that is arithmetically meaningless — the
  # reader cannot tell it from a stale token and would go looking at the TTL. The arm itself is
  # load-bearing either way: without it a future-dated record is never `-gt ttl`, so it ADMITS.
  if [ "$age" -lt 0 ]; then
    CC_ADMIT_TOKEN_NOTE="token issued in the FUTURE (${age}s, i.e. minted $(( 0 - age ))s ahead of this clock) — a skew or a forgery, never an admission; consumed, evaluating fresh${CC_ADMIT_TOKEN_UNLINK:+ [${CC_ADMIT_TOKEN_UNLINK}]}"
    return 1
  fi
  if [ "$age" -gt "$ttl" ]; then
    CC_ADMIT_TOKEN_NOTE="token EXPIRED (${age}s old > TTL ${ttl}s) — consumed, evaluating fresh${CC_ADMIT_TOKEN_TTL_NOTE:+ [${CC_ADMIT_TOKEN_TTL_NOTE}]}${CC_ADMIT_TOKEN_UNLINK:+ [${CC_ADMIT_TOKEN_UNLINK}]}"
    return 1
  fi
  CC_ADMIT_TOKEN_NOTE="${CC_ADMIT_TOKEN_TTL_NOTE}${CC_ADMIT_TOKEN_TTL_NOTE:+ }${CC_ADMIT_TOKEN_UNLINK}"
  CC_ADMIT_TOKEN_AGE="$age"; CC_ADMIT_TOKEN_SID="$sid"; CC_ADMIT_TOKEN_TERMS="$terms"
  return 0
}

# ── THE NON-CHARGING PROBE (LIMIT_RECOVER_100P, 2026-09-09) ─────────────────────────────────────
# A fleet recovery must never type /exit into a pane it cannot relaunch, so it asks the box BEFORE
# the irreversible keystroke — and asking must not SPEND the refusal budget that protects the box,
# or three probes in a loop would force the fourth spawn in (the "never spend the third refusal"
# constraint in docs/plans/LIMIT_RECOVER_100P.md §4). cc_capacity_probe evaluates the identical
# terms, in the identical order, with the identical thresholds — it is cc_capacity_admit with the
# budget file, the page and the reset all inert — and reports its verdict on the IDL under
# basis `probe` so a wait-then-park sequence is auditable. Same 0/9 contract; CC_ADMIT_REASON set.
cc_capacity_probe() { # $1=caller $2=what → 0 would-admit / 9 would-refuse · charges NOTHING
  local rc=0
  _CC_ADMIT_PROBE=1
  cc_capacity_admit "$1" "$2" || rc=$?
  _CC_ADMIT_PROBE=0
  return "$rc"
}
_CC_ADMIT_PROBE=0

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
  local tok_occ tok_rep tok_pgmax

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

  # ── REDEEM AN ADMISSION TOKEN (W2) ─────────────────────────────────────────────────────────────
  # Placed immediately after the kill switch and BEFORE every term, because the whole point is that
  # the terms were already evaluated — by the driver, on this box, ≤ TTL ago, for THIS sid. `token`
  # is an EIGHTH basis value; adding here is the legal direction (coverage case 27 requires
  # capacity_gate's vocabulary to stay a SUBSET of this one, never the reverse).
  # The reset is the ordinary one: a redeemed admission ends a consecutive-refusal run exactly as a
  # measured admit does.
  CC_ADMIT_TOKEN_NOTE=""; CC_ADMIT_TOKEN_TERMINAL=""; CC_ADMIT_TOKEN_IDENT=""; CC_ADMIT_TOKEN_REPEAT=""
  if [ "${_CC_ADMIT_PROBE:-0}" != 1 ] && [ -n "${CC_ADMIT_TOKEN:-${LR_ADMIT_TOKEN:-}}" ]; then
    if _cc_admit_token_redeem; then
      CC_ADMIT_REASON="capacity-admit: ADMIT (admission token, ${CC_ADMIT_TOKEN_AGE}s old, issued for ${CC_ADMIT_TOKEN_SID}) — one decision, redeemed once"
      _cc_admit_emit admit token "$caller" "$what" \
        "redeemed a probe admission ${CC_ADMIT_TOKEN_AGE}s old for ${CC_ADMIT_TOKEN_SID} (TTL ${CC_ADMIT_TOKEN_TTL_VALUE}s; minted under terms ${CC_ADMIT_TOKEN_TERMS:-?})"
      _cc_admit_reset "$caller"; return 0
    fi
    # ── THE TERMINAL STATE (W2FA D5) ───────────────────────────────────────────────────────────
    # Reached only when the record was THIS spawn's own admission and could not be used. Evaluating
    # the box fresh here is precisely the failure the wave closes: the driver already decided, this
    # process cannot see that decision, and 11-16 s later it renders a contradictory one — in the
    # pane, after the transplant. Four husks on 2026-09-19. So the gate stops, names the state, and
    # pages; it does not re-decide.
    #
    # NOT a spend, deliberately: `_cc_admit_spend` bounds refusals that are about the BOX, and this
    # one is about the caller's own input. Charging it would let three stale tokens release a spawn
    # — a silent admit on exactly the evidence that just failed. §9's law is still satisfied,
    # because this state cannot stand: the token is one-shot, so the next fire mints a new one, and
    # a re-typed relaunch over a CONSUMED token reads ABSENT and falls through as it always did.
    # Every occurrence pages, which is the law's "converts the standing state into an EVENT".
    if [ "$CC_ADMIT_TOKEN_TERMINAL" = 1 ] && [ "${CC_ADMIT_TOKEN_REQUIRED:-on}" != off ]; then
      # BOUNDED, AND A REPEAT IS DISTINGUISHABLE FROM THE FIRST (W2FA A1 — see the counter's
      # header). The verdict below is identical at occurrence 1 and occurrence 100; only the ALARM
      # is bounded, and only the wording changes.
      tok_occ="$(_cc_admit_token_occurrence "$CC_ADMIT_TOKEN_IDENT")"
      CC_ADMIT_TOKEN_REPEAT="$tok_occ"
      if [ "$tok_occ" -gt 1 ]; then
        tok_rep=" THIS IS REPEAT #${tok_occ}: the same record has now failed to redeem ${tok_occ} times and is STILL on disk, so re-running this command cannot change the outcome — the driver must mint a new one."
      else
        tok_rep=""
      fi
      CC_ADMIT_REASON="capacity-admit: REFUSING ${what} — this spawn's OWN admission token could not be redeemed (${CC_ADMIT_TOKEN_NOTE}). Evaluating the box again HERE would be the second gate on one net-zero operation, in the pane, after the transplant. Re-fire (the driver mints a fresh token), or override this one refusal with CC_ADMIT_TOKEN_REQUIRED=off.${tok_rep}"
      _cc_admit_emit refuse token-stale "$caller" "$what" \
        "the driver's admission for this spawn could not be redeemed — refusing rather than re-deciding in the pane (TTL ${CC_ADMIT_TOKEN_TTL_VALUE}s; occurrence ${tok_occ}${CC_ADMIT_TOKEN_OCC_NOTE:+ — ${CC_ADMIT_TOKEN_OCC_NOTE}})" token
      tok_pgmax="${CC_ADMIT_TOKEN_TERMINAL_PAGES:-1}"
      cc_hw_is_int_operand "$tok_pgmax" || CC_HW_INT_VALUE=1
      if [ "$tok_occ" -le "$CC_HW_INT_VALUE" ]; then
        _cc_admit_page "⚠️ capacity-admit: ${caller} REFUSED '${what}' — this spawn's own admission token could not be redeemed (${CC_ADMIT_TOKEN_NOTE}). Nothing was spawned and no term was evaluated; re-fire to mint a fresh admission."
      fi
      return 9
    fi
    # Everything else falls through, and never silently: CC_ADMIT_TOKEN_NOTE rides on whatever row
    # this evaluation writes, so "the launcher evaluated fresh" always carries WHY.
    :
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
  # 8 is the top of the measured band — and the BAND is what survives, not the per-session figure it
  # used to be derived from. This comment read "Axis 09: 2.5-5 runnable threads per genuinely-ACTIVE
  # session (load1 27.4 -> 44.4 at 9 all-active)". That figure is an aggregate/N — a RATIO, not a
  # marginal — and its own cited pair yields 1.89, not 2.5-5. REFUTED and UNQUOTABLE: see
  # docs/research/marginal-load-per-active-session-2026-08-19.md §2 (backlog 193ae8ddce72), which
  # adjudicates all four published values (0.172 / 0.566 / 1.89 / 2.5-5) as unrepairable and bans
  # quoting any of them until scripts/capacity-marginal.sh clears its three controls on the box (§6).
  #
  # ✅ MEASURED 2026-09-08 (§6e) — the ban's condition is discharged, and this is the ONLY quotable
  # value: 2.390 load units per ACTIVE session, +/- 0.533 (1 s.e.). Window: n=85, n_eff=85.0,
  # span 5202s, proc unit, load1 14.97..154.89 (10.35x); C1 swing 1.18x, C2 corr 0.835, C3 active
  # 5..11 over 7 levels. Raw window committed at docs/research/data/capacity-marginal-2026-09-08.tsv
  # — re-run `capacity-marginal.sh analyze --in` on it to reproduce this line exactly.
  # QUOTE IT ONLY WITH THE S.E. AND THE WINDOW; a bare 2.390 is how the last four values got loose.
  # It is an UPPER bound on cost per active session, because cc_sp_active is a proven LOWER bound.
  # That is the correct direction for a ceiling and the WRONG one for a "+N sessions" projection —
  # do not invert it.
  #
  # WHAT STILL HOLDS, and why the ceiling is not blocked on that measurement: ~4-8 concurrent actives
  # is what all 127/127 historic gate refusals correspond to. That is a COUNT OVER REFUSALS, derived
  # without dividing by any per-session coefficient, so the adjudication does not touch it — it is
  # the band 8 sits at the top of. The TOP of the band is deliberate: this term refuses real work, so
  # it must bind where the evidence is unambiguous, and the load and segment terms above already
  # cover the middle of the band from their own directions.
  #
  # DO NOT substitute another number here. §6 of that doc said to update this site to the MEASURED
  # value once the on-box window had been run — never to one of the other three. THAT RUN HAPPENED
  # (2026-09-08) and its value is quoted above, so this is a discharged instruction, not an open
  # one: there is nothing left to go and measure on this axis, and a session that reads this
  # paragraph as an errand is re-deriving a landed result.
  #
  # THE CEILING 8 IS UNCHANGED BY THAT MEASUREMENT, deliberately. It stands on the 127/127 refusal
  # band above — a count over refusals — and was never derived by dividing by a per-session
  # coefficient, so a coefficient cannot move it. Changing this literal is a gate-threshold change
  # and needs its own evidence and its own decision, not an arithmetic consequence of 2.390.
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
  if [ "${_CC_ADMIT_PROBE:-0}" = 1 ]; then
    # A probe refusal is a MEASUREMENT, not a spend: no budget file touched, no page, no release.
    CC_ADMIT_REASON="capacity-admit: PROBE would REFUSE ${what} — ${detail} (nothing charged; the caller waits or parks)"
    _cc_admit_emit refuse probe "$caller" "$what" "${detail} (probe — budget untouched)" "$term"
    return 9
  fi
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
