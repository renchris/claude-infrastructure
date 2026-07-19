#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the `<check> && ok || bad` reporter idiom is intentional —
# ok/bad always return 0 (printf + arithmetic), so SC2015's "C runs when A true but B fails" cannot occur.
#
# never-stuck-gate — THE SYSTEMATIC INVARIANT (B1-c): one audited composition over every layer built
# by this track, proving the standing claim:
#
#     Every live session, at every moment, is either
#        (a) making PROGRESS,
#        (b) at an OWNED WAIT with a deadline,
#        (c) at a DESIGNED GATE / blocked-on-operator, or
#        (d) CLEANLY TERMINATED
#     — never silently idle with work remaining.
#
# The pieces each hold one edge (wait-contracts own the waits; reap-guard protects the living;
# comms make completion loud; the poller re-fires limit-parked sessions; cc-respawn delivers GOs;
# cc-route stops at cliffs). What was MISSING is the thing this gate is: a single audit that the
# composition HOLDS — every component green, every state guarded, every known failure class covered,
# and the runtime wiring inventory visible. A composition nobody can watch fire is itself a check
# that cannot observe what it guards (the premortem-gate lesson, one layer up).
#
# LEG 1  COMPONENT GATES — all seven sibling bars run LIVE; a missing gate is RED (absent ≠ passing).
# LEG 2  STATE COVERAGE — each invariant state (a)-(d) names its guardian artifacts; existence checked.
# LEG 3  FAILURE-CLASS COVERS — the corpus taxonomy, each class → its mechanical cover.
# LEG 4  RUNTIME INVENTORY — read-only ACTIVE/C10-PENDING report. NEVER a failure: build-complete and
#        activation-complete are DIFFERENT bars (Invariant 6 / the C10 line) — this gate proves the
#        first and only REPORTS the second. Activation is the operator's hand (wiring-all.sh).
#
#   never-stuck-gate.sh              full audit (legs 1-4)
#   never-stuck-gate.sh --selftest   RED-proof of the composition mechanics (fail-closed: one red
#                                    component → RED; a MISSING component → RED; all green → GREEN)
#
# Env: CC_NS_REPO_DIR (selftest sandbox — runs LEG 1 only against stub gates).
# Exit: 0 = the invariant's build bar holds · 1 = broken (with the failing leg named).
set -uo pipefail

if [ -n "${CC_NS_REPO_DIR:-}" ]; then REPO="$CC_NS_REPO_DIR"; LEG1_ONLY=1
else
  # resolve $0 through symlinks first: invoked via ~/.claude/scripts/<link>, dirname $0/.. lands in
  # ~/.claude and 4 checks go red while the direct repo path stays green (C4 caught it 2026-07-19;
  # same $0 class as the reaper-launchd-path fix)
  _src="$0"
  while [ -L "$_src" ]; do
    _d="$(cd "$(dirname "$_src")" && pwd)"
    _src="$(readlink "$_src")"
    case "$_src" in /*) ;; *) _src="$_d/$_src" ;; esac
  done
  REPO="$(cd "$(dirname "$_src")/.." && pwd)"; LEG1_ONLY=0
fi

PASS=0; FAIL=0
ok(){   printf '  ✅ %-8s %s\n' "$1" "$2"; PASS=$((PASS+1)); }
bad(){  printf '  ⛔ %-8s %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
info(){ printf '  · %-10s %s\n' "$1" "$2"; }

COMPONENT_GATES="wait-safety-gate reaper-safety-gate comms-safety-gate limit-reset-safety-gate respawn-safety-gate route-safety-gate premortem-gate"

run_leg1() {
  echo "LEG 1 — component gates (live runs; a missing bar is a broken bar):"
  local g f rc
  for g in $COMPONENT_GATES; do
    f="$REPO/scripts/$g.sh"
    if [ ! -f "$f" ]; then
      bad "$g" "ABSENT — a bar that does not exist cannot be green (fail-closed: absent ≠ passing)"
      continue
    fi
    if bash "$f" >/dev/null 2>&1; then ok "$g" "GREEN"
    else rc=$?; bad "$g" "RED (exit $rc) — run scripts/$g.sh for the failing criterion"; fi
  done
}

exists_all() { # <label> <desc> <path...>
  local label="$1" desc="$2"; shift 2
  local missing="" p
  for p in "$@"; do [ -e "$REPO/$p" ] || missing="$missing $p"; done
  if [ -z "$missing" ]; then ok "$label" "$desc"
  else bad "$label" "$desc — MISSING:$missing"; fi
}

run_leg2() {
  echo
  echo "LEG 2 — the four states, each with a live guardian:"
  exists_all "(a)" "PROGRESS is observable: effect-bound heartbeats (cc-run) + self-telemetry (cc-context reads the statusline export)" \
    bin/cc-run bin/cc-context
  exists_all "(b)" "WAITS are OWNED: disk contracts with deadline+action (cc-wait) + the auditor/watchdog (wait-contract-lint --sweep)" \
    bin/cc-wait scripts/wait-contract-lint.sh
  exists_all "(c)" "DESIGNED GATES are attested + loud: content-sha ruling binds (cc-bind) + operator completion-push (F5) + exit-deadline tightening (F4)" \
    bin/cc-bind scripts/completion-push.sh scripts/exit-deadline.sh
  exists_all "(d)" "TERMINATION is clean + verified: safety-gated teardown (cc-teardown + decision module) + birth-grace reap-guard + capture-before-notify deathwatch" \
    bin/cc-teardown bin/cc-teardown-safety-gate.sh scripts/reap-guard.sh scripts/lead-deathwatch.sh
}

run_leg3() {
  echo
  echo "LEG 3 — failure-class covers (the corpus taxonomy; every class a mechanical cover):"
  exists_all "NS-1" "spawn-death / never-rendered → P8 registry (cc-sessions) + cc-board DIED-UNRENDERED join" \
    bin/cc-sessions bin/cc-board
  exists_all "NS-2" "dead peer / dead waiter → kqueue exit-instant deathwatch + L2-c sweep (waiter {pid,start} identity)" \
    bin/cc-deathwatch-kqueue scripts/lead-deathwatch.sh
  exists_all "NS-3" "hung-but-alive (silent hang) → cc-run output-beats break the D10 identity; page-only supervisor re-observes (S-3b)" \
    bin/cc-run scripts/lead-supervisor.sh
  exists_all "NS-4" "roster divergence (harness×registry×disk) → three-way anti-entropy reconciler" \
    scripts/lead-reconciler.sh
  exists_all "NS-5" "premature reap → birth-grace + effect-read reap-guard; horizon + silence-reap lints standing" \
    scripts/reap-guard.sh scripts/reaper-horizon-lint.sh scripts/s3b-lint.sh
  exists_all "NS-6" "silent completion → VERIFIED-or-LOUD announce (F1) + program-terminal operator push (F5) + payload back-channel lint (F3)" \
    bin/cc-announce scripts/completion-push.sh scripts/payload-lint.sh
  exists_all "NS-7" "mid-sequence stall (turn ends between steps) → session-continue arming hook + F4 exit-sequence sweep-tightening" \
    hooks/session-continue.sh scripts/exit-deadline.sh
  exists_all "NS-8" "limit-park (killed by a usage limit, idle forever) → reset-watching poller (B1-d, LR-a..i proven)" \
    scripts/limit-recover/lr-reset-poller.sh scripts/limit-recover/com.reso.lr-reset-poller.plist
  exists_all "NS-9" "undelivered mid-stream GO → respawn-as-protocol (B1-a, RS-a..f proven; the mailbox is structurally unexpressible)" \
    bin/cc-respawn
  exists_all "NS-10" "blind routing / silent down-tier / cliff fire → live-read router (B1-b, RT-a..f proven; cliff = STOP)" \
    bin/cc-route
}

run_leg4() {
  echo
  echo "LEG 4 — runtime inventory (READ-ONLY; activation is the operator's hand — never a failure here):"
  local t
  for t in cc-wait cc-run cc-announce cc-deathwatch-kqueue cc-sessions cc-context cc-board cc-bind cc-teardown cc-respawn cc-route; do
    if [ -L "$HOME/.claude/bin/$t" ] && [ -e "$HOME/.claude/bin/$t" ]; then
      case "$(readlink "$HOME/.claude/bin/$t")" in
        *claude-infrastructure*) info "ACTIVE" "$t → symlinked live into the repo" ;;
        *) info "DRIFT?" "$t → symlink resolves OUTSIDE the repo (verify before trusting)" ;;
      esac
    elif [ -e "$HOME/.claude/bin/$t" ]; then info "COPY?" "$t → present but NOT a symlink (Deploy-DoD drift risk — repo edits will not propagate)"
    else info "C10-PEND" "$t → not deployed (operator hand-step in wiring-all.sh)"; fi
  done
  if launchctl list 2>/dev/null | grep -q 'com.claude.lead-supervisor'; then
    info "ACTIVE" "lead-supervisor launchd loaded (page-only sweeps live)"
  else info "C10-PEND" "lead-supervisor launchd NOT loaded"; fi
  if launchctl list 2>/dev/null | grep -q 'com.reso.lr-reset-poller'; then
    info "ACTIVE" "lr-reset-poller launchd loaded"
  else info "C10-PEND" "lr-reset-poller launchd NOT loaded (plist install + LR_POLLER_AUTOFIRE=1 = operator hand-steps)"; fi
}

selftest() {
  local tmp pass=0 fail=0 rc SELF
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/never-stuck-selftest.XXXXXX")" || { echo "cannot mktemp" >&2; exit 2; }
  trap 'rm -rf "${tmp:-}"' EXIT
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  mkdir -p "$tmp/scripts"
  local g
  for g in $COMPONENT_GATES; do printf '#!/bin/bash\nexit 0\n' > "$tmp/scripts/$g.sh"; done

  check() { local label="$1" want="$2"; shift 2
    "$@" >/dev/null 2>&1; rc=$?
    if [ "$rc" = "$want" ]; then printf '  ok   %-58s (exit %s)\n' "$label" "$rc"; pass=$((pass+1))
    else printf '  FAIL %-58s (exit %s, wanted %s)\n' "$label" "$rc" "$want"; fail=$((fail+1)); fi
  }

  echo "never-stuck-gate selftest — the composition itself must be fail-closed:"
  check "all components green -> composition GREEN" 0 env CC_NS_REPO_DIR="$tmp" "$SELF"
  printf '#!/bin/bash\nexit 1\n' > "$tmp/scripts/route-safety-gate.sh"
  check "ONE red component -> composition RED" 1 env CC_NS_REPO_DIR="$tmp" "$SELF"
  check "the RED names the failing gate" 0 \
    bash -c "env CC_NS_REPO_DIR='$tmp' '$SELF' 2>/dev/null | grep -q '⛔ route-safety-gate'"
  printf '#!/bin/bash\nexit 0\n' > "$tmp/scripts/route-safety-gate.sh"
  rm -f "$tmp/scripts/premortem-gate.sh"
  check "a MISSING component -> composition RED (absent ≠ passing)" 1 env CC_NS_REPO_DIR="$tmp" "$SELF"

  echo "never-stuck-gate selftest: $pass passed, $fail failed"
  [ "$fail" -eq 0 ] || exit 1
  exit 0
}

case "${1:-}" in --selftest) selftest ;; esac

echo "never-stuck-gate — the systematic invariant: progressing | owned-wait | designed-gate | terminated — never silently idle with work remaining"
echo
run_leg1
if [ "$LEG1_ONLY" -eq 0 ]; then
  run_leg2
  run_leg3
  run_leg4
  # ── DECLARED BLINDNESSES (composition rule: every blindness names its cover) ─────────────────────
  echo
  echo "  🕳  NS-blind-1: session-continue arming is VOLUNTARY (an un-armed turn-end is allowed by the"
  echo "      harness) → covered by F4's ~900s exit-sequence sweep, the supervisor's D10 stall page, and"
  echo "      the JSONL-tail nudge recipe (mid-sequence-stall-detection). The stall is caught, not prevented."
  echo "  🕳  NS-blind-2: idle-with-open-BACKLOG is SEMANTIC — no mechanical check can judge scope-"
  echo "      completeness against a prose DoD → covered by the async-queue-as-worklist law (briefs +"
  echo "      memory), F5 completion-push (every terminal claim reaches the operator), and peers' wait-"
  echo "      contracts on expected deliverables. A machine-readable DoD registry would close it fully."
fi
echo
printf 'never-stuck-gate: %d met · %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "⇒ THE INVARIANT IS BROKEN — a session CAN currently go silently idle through the failing leg."
  exit 1
fi
if [ "$LEG1_ONLY" -eq 0 ]; then
  echo "⇒ the never-stuck invariant HOLDS at the build bar: every component green, every state guarded,"
  echo "   every known failure class covered. Runtime wiring per LEG 4 (activation = wiring-all.sh, operator's hand);"
  echo "   wire this gate onto the supervisor sweep cadence so the composition is WATCHED, not assumed."
else
  echo "⇒ composition mechanics GREEN (sandbox mode: LEG 1 only)."
fi
