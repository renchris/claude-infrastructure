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
# reading as the gate healthy. SPLIT ON `basis` BEFORE BELIEVING ANY RATIO COMPUTED FROM THESE ROWS.
#
# ── Caller contract ────────────────────────────────────────────────────────────────────────────
#   . scripts/lib/capacity-admit.sh
#   cc_capacity_admit <caller> [what]     → 0 = ADMIT, 9 = REFUSE
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
#      CC_ADMIT_BUDGET(3) · CC_ADMIT_SYSCTL · CC_ADMIT_LOADAVG_OVERRIDE · CC_ADMIT_HEADROOM_OVERRIDE ·
#      CC_ADMIT_STATE_DIR · CC_ADMIT_IDL · CC_ADMIT_NOTIFY_BIN ·
#      CC_ADMIT_LOAD_TERM(on) · CC_ADMIT_HEADROOM_TERM(on)  — per-caller term selection
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
# (tests/capacity-admit-coverage.bats case 26 is the ratchet). 2.0/core is §9.5's measured ceiling;
# 4 GB is M10's reclaimable floor.
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

# ── the verdicts ───────────────────────────────────────────────────────────────────────────────
# Both are pure awk over already-validated numbers, so they cannot fail and cannot record: WHAT to
# do with a REFUSE is the policy each gate owns (refuse unboundedly, or spend a unit of budget).
cc_hw_load_verdict() { # $1=load $2=ncpu $3=ceiling → "REFUSE 2.72" | "ADMIT 0.10"
  awk -v l="$1" -v n="$2" -v c="$3" \
    'BEGIN { lpc = l / n; printf "%s %.2f", (lpc > c ? "REFUSE" : "ADMIT"), lpc }'
}
cc_hw_headroom_verdict() { # $1=reclaimable GB $2=floor GB → REFUSE | ADMIT
  awk -v h="$1" -v f="$2" 'BEGIN { print (h < f ? "REFUSE" : "ADMIT") }'
}

# ── the validators ─────────────────────────────────────────────────────────────────────────────
# Every caller fails OPEN on a false here — a gate must never convict on its own unreadable input.
cc_hw_is_int() { case "${1:-}" in ''|*[!0-9]*)  return 1 ;; esac; return 0; }
cc_hw_is_num() { case "${1:-}" in ''|*[!0-9.]*) return 1 ;; esac; return 0; }
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
  jq -cn --arg ts "$ts" --arg disp "$( [ "$1" = admit ] && echo admitted || echo refused )" \
         --arg v "$1" --arg b "$2" --arg c "$3" --arg w "$4" --arg d "$5" --arg t "${6:-}" \
         --arg sid "${CC_ADMIT_SID:-?}" \
    '{ts:$ts,hook:"capacity-admit",sid:$sid,disposition:$disp,reason:"capacity",
      gate:"capacity-admit",verdict:$v,basis:$b,caller:$c,what:$w,detail:$d}
     + (if $t == "" then {} else {term:$t} end)' >> "$idl" 2>/dev/null || true
  return 0
}

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
  sysctl_bin="$(cc_hw_resolve_sysctl "${CC_ADMIT_SYSCTL:-}")"
  ncpu="$(cc_hw_ncpu "$sysctl_bin")"
  load="$(cc_hw_load1 "$sysctl_bin")"
  [ -n "${CC_ADMIT_LOADAVG_OVERRIDE:-}" ] && load="$CC_ADMIT_LOADAVG_OVERRIDE"
  ceiling="${CC_ADMIT_MAX_LOAD_PER_CORE:-$CC_HW_DEFAULT_MAX_LOAD_PER_CORE}"
  budget="${CC_ADMIT_BUDGET:-3}"

  if ! cc_hw_is_int "$ncpu"; then
    CC_ADMIT_REASON="capacity-admit: hw.ncpu unreadable ('$ncpu') via $sysctl_bin -> ADMIT (fail-open)"
    _cc_admit_emit admit fail-open "$caller" "$what" "hw.ncpu unreadable ('$ncpu') via $sysctl_bin"
    _cc_admit_reset "$caller"; return 0
  fi
  if ! cc_hw_is_num "$load"; then
    CC_ADMIT_REASON="capacity-admit: vm.loadavg unreadable ('$load') via $sysctl_bin -> ADMIT (fail-open)"
    _cc_admit_emit admit fail-open "$caller" "$what" "vm.loadavg unreadable ('$load') via $sysctl_bin"
    _cc_admit_reset "$caller"; return 0
  fi
  if ! cc_hw_is_num "$ceiling"; then
    CC_ADMIT_REASON="capacity-admit: bad CC_ADMIT_MAX_LOAD_PER_CORE ('$ceiling') -> ADMIT (fail-open)"
    _cc_admit_emit admit fail-open "$caller" "$what" "bad CC_ADMIT_MAX_LOAD_PER_CORE ('$ceiling')"
    _cc_admit_reset "$caller"; return 0
  fi
  # A bad budget must fail to the side that keeps the gate BOUNDED — i.e. admit. A typo that made
  # this gate unbounded would re-create the §12.2 outage, so the unsafe direction is refusal.
  # NOT a shared term: the bound is this gate's own policy and capacity_gate() deliberately has none.
  if ! cc_hw_is_int "$budget"; then
    CC_ADMIT_REASON="capacity-admit: bad CC_ADMIT_BUDGET ('$budget') -> ADMIT (fail-open)"
    _cc_admit_emit admit fail-open "$caller" "$what" "bad CC_ADMIT_BUDGET ('$budget') — bound unusable"
    _cc_admit_reset "$caller"; return 0
  fi
  if [ "$ncpu" -le 0 ]; then
    CC_ADMIT_REASON="capacity-admit: hw.ncpu=0 -> ADMIT (fail-open)"
    _cc_admit_emit admit fail-open "$caller" "$what" "hw.ncpu=0"
    _cc_admit_reset "$caller"; return 0
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
    if [ "${CC_ADMIT_LOAD_TERM:-on}" = off ]; then
      # BOTH terms off = no term evaluated at all. This is `gate-off` however it was spelled, and it
      # must record as such: a row reading `load-only` with the load term also off would count a
      # blind evaluation as a real one, which is the §9.5.1 population defect exactly.
      CC_ADMIT_REASON="capacity-admit: ADMIT — both terms off, nothing evaluated"
      _cc_admit_emit admit gate-off "$caller" "$what" "CC_ADMIT_LOAD_TERM=off and CC_ADMIT_HEADROOM_TERM=off"
      _cc_admit_reset "$caller"; return 0
    fi
    CC_ADMIT_REASON="capacity-admit: ADMIT (load only) — ${lpc}/core (ceiling ${ceiling}/core)"
    _cc_admit_emit admit load-only "$caller" "$what" \
      "load ${load} on ${ncpu} cores = ${lpc}/core (ceiling ${ceiling}/core) · headroom term off"
    _cc_admit_reset "$caller"; return 0
  fi
  floor="${CC_ADMIT_MIN_HEADROOM_GB:-$CC_HW_DEFAULT_MIN_HEADROOM_GB}"
  if [ -n "${CC_ADMIT_HEADROOM_OVERRIDE:-}" ]; then
    head_gb="$CC_ADMIT_HEADROOM_OVERRIDE"
  else
    head_gb="$(cc_hw_headroom_gb)" || head_gb=""
  fi
  if ! cc_hw_is_num "$floor"; then
    CC_ADMIT_REASON="capacity-admit: bad CC_ADMIT_MIN_HEADROOM_GB ('$floor') -> ADMIT (fail-open)"
    _cc_admit_emit admit fail-open "$caller" "$what" "bad CC_ADMIT_MIN_HEADROOM_GB ('$floor')"
    _cc_admit_reset "$caller"; return 0
  fi
  if ! cc_hw_is_num "$head_gb"; then
    CC_ADMIT_REASON="capacity-admit: reclaimable headroom unreadable ('$head_gb') -> ADMIT (fail-open)"
    _cc_admit_emit admit fail-open "$caller" "$what" "reclaimable headroom unreadable ('$head_gb')"
    _cc_admit_reset "$caller"; return 0
  fi
  if [ "$(cc_hw_headroom_verdict "$head_gb" "$floor")" = REFUSE ]; then
    detail="reclaimable ${head_gb}GB < floor ${floor}GB"
    _cc_admit_spend "$caller" "$what" "$budget" "$detail" "headroom"; return $?
  fi

  # `measured` means what a naive reader assumes "admit" means: EVERY ENABLED term read a live
  # instrument and cleared. A caller running one term gets `headroom-only`/`load-only` instead, so a
  # single-term window can never be counted as evidence that both were exercised.
  if [ "${CC_ADMIT_LOAD_TERM:-on}" = off ]; then
    CC_ADMIT_REASON="capacity-admit: ADMIT (headroom only) — reclaimable ${head_gb}GB (floor ${floor}GB)"
    _cc_admit_emit admit headroom-only "$caller" "$what" \
      "reclaimable ${head_gb}GB (floor ${floor}GB) · load term off"
    _cc_admit_reset "$caller"; return 0
  fi
  CC_ADMIT_REASON="capacity-admit: ADMIT — ${lpc}/core (ceiling ${ceiling}/core) · reclaimable ${head_gb}GB (floor ${floor}GB)"
  _cc_admit_emit admit measured "$caller" "$what" \
    "load ${load} on ${ncpu} cores = ${lpc}/core (ceiling ${ceiling}/core) · reclaimable ${head_gb}GB (floor ${floor}GB)"
  _cc_admit_reset "$caller"
  return 0
}

# ── spend one unit of budget, or convert the standing state into an event ──────────────────────
# This is the entire §9 law in one function: a would-be refusal is only allowed to BE a refusal
# while budget remains. Past it the gate admits and pages, so a saturated box delays a spawn and
# can never stand as a permanent refusal — the §12.2 outage, made structurally unreachable.
_cc_admit_spend() { # $1=caller $2=what $3=budget $4=detail $5=term → 0 admit / 9 refuse
  local caller="$1" what="$2" budget="$3" detail="$4" term="$5" sf n
  sf="$(_cc_admit_state_file "$caller")"
  if [ -z "$sf" ]; then
    # An unusable caller id means the bound cannot be tracked, and an UNTRACKED bound is an
    # UNBOUNDED gate. Refusing here would convict on our own bad wiring, so admit and say so.
    CC_ADMIT_REASON="capacity-admit: ADMIT (fail-open) — caller id '$caller' cannot key the budget; bound untrackable"
    _cc_admit_emit admit fail-open "$caller" "$what" "caller id unusable — bound untrackable ($detail)"
    return 0
  fi
  n="$(cat "$sf" 2>/dev/null || echo 0)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  n=$((n + 1))
  if [ "$n" -gt "$budget" ]; then
    CC_ADMIT_REASON="capacity-admit: ADMIT (budget expired after ${budget} consecutive refusals) — ${detail}"
    _cc_admit_emit admit budget-expired "$caller" "$what" \
      "${term} term over after ${budget} consecutive refusals — admitting and paging: ${detail}" "$term"
    _cc_admit_page "⚠️ capacity-admit: ${caller} spent its ${budget}-refusal budget and is ADMITTING '${what}' into a saturated box — ${detail}. Shed load (close finished panes) or raise the bar."
    : > "$sf" 2>/dev/null || true
    return 0
  fi
  printf '%s\n' "$n" > "$sf" 2>/dev/null || true
  CC_ADMIT_REASON="capacity-admit: REFUSING ${what} — ${detail} (refusal ${n} of ${budget}; once the budget is spent the next evaluation ADMITS and pages)"
  # basis stays `measured` — BOTH instruments read fine; it is the box that is over, not the probe.
  # WHICH term refused is a separate field: folding it into `basis` would corrupt the one vocabulary
  # §9.5.1 requires you to split on before believing any ratio computed from these rows.
  _cc_admit_emit refuse measured "$caller" "$what" "${detail} (refusal ${n} of budget ${budget})" "$term"
  return 9
}
