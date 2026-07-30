#!/bin/bash
# test-hermeticity-lint — a RATCHET on test-suite hermeticity.
#
# WHY: a bats suite that does not fixture $HOME runs its subject against the OPERATOR'S REAL state —
# ~/.claude/autonomy/idl.jsonl, ~/.reso ledgers, ~/.claude/mailbox. Two costs, both observed
# (2026-07-25 flaky-gate sweep): the suite MUTATES live state (404 stray idl.jsonl lines traced to
# one unfixtured suite), and it READS live state, so its result depends on whatever the desk happens
# to be doing — the textbook flake. $HOME is the single highest-leverage seam because nearly every
# tool in this repo resolves its state dir under it.
#
# WHY A RATCHET AND NOT A FLAG-DAY: 109 of 118 suites are unfixtured today. Fixing them all at once
# is a bigger change than anyone will review honestly, and a lint nobody can turn on is worth zero.
# So: the existing 109 are grandfathered by name, and the rule binds only where it is free — NEW
# suites. The list can only SHRINK. Fixing a suite is therefore a two-line change (fixture $HOME,
# delete its allowlist line) and the lint FAILS if you fixture one and forget to delete the line,
# which is what stops a ratchet from silently becoming a permanent exemption list.
#
# RULE 1 ($HOME): a suite is hermetic iff its setup() or setup_file() body sets a fixture HOME
# (`export HOME=` or `HOME="$BATS...`). Per-test HOME does not count — it leaves every OTHER test
# in the file pointed at live state, which is exactly the failure this catches.
#
# RULE 2 (the fire capacity gate) — the SAME CLASS, found 2026-07-29 and folded into this ratchet
# rather than given a guard of its own, because the failure, the remedy and the ratchet contract are
# identical; only the seam differs. handoff-fire.sh's `capacity_gate()` (scripts/handoff-fire.sh,
# `CC_FIRE_CAPACITY_GATE`) reads LIVE `sysctl vm.loadavg` and REFUSES a net-new fire at >= 2.0
# load/core (exit 9). This box sits permanently at 3.4-7.3/core. So a suite that exercises a net-new
# fire WITHOUT pinning the gate off does not test its subject at all: it reads AMBIENT MACHINE LOAD
# and goes red-by-load — the same "result depends on whatever the desk happens to be doing" flake
# that rule 1 exists to kill. Proven two-sided at 3.39/core on tests/fire-engagement.bats (ambient ->
# `not ok 14`; `CC_FIRE_CAPACITY_GATE=off` -> `ok 14`).
#   A suite is compliant iff it does NOT reference handoff-fire at all (out of scope — never
#   flagged), or its setup()/setup_file() BODY contains `CC_FIRE_CAPACITY_GATE=off` (export or
#   inline env). Per-test pinning does NOT count, for rule 1's reason verbatim: it leaves every
#   other test in the file reading ambient state.
#   Rule 2 carries its OWN grandfather list (EMBEDDED_FIRE_ALLOWLIST), separate from rule 1's and
#   under the same contract — ONLY EVER DELETE LINES; pinning a suite without deleting its line is
#   a RED, which is what stops a ratchet from decaying into a permanent exemption list.
#
# Exit: 0 = clean · 1 = violation · 2 = bad usage / unreadable scan dir (LOUD, never silent-green)
#
# Env seams (selftest / escape hatch):
#   CC_HERM_ALLOWLIST       overrides rule 1's embedded allowlist (set-but-empty = no grandfathering)
#   CC_HERM_FIRE_ALLOWLIST  overrides rule 2's embedded allowlist (same set-but-empty semantics)
#   CC_HERM_FIRE_RULE=off   kill switch — disables rule 2 entirely, leaving rule 1 exactly as it was
set -uo pipefail
# Resolve $0 THROUGH symlinks before deriving ROOT. Everything under ~/.claude/scripts/ is a per-file
# symlink into this checkout, so a bare `dirname "$0"` yields ~/.claude — which has no tests/ — and the
# --selftest case that lints the real tree then fails for a reason that has nothing to do with the
# ratchet. Observed 2026-07-26 running the DEPLOYED path right after landing it. (No `readlink -f`:
# that is GNU-only and this box ships the BSD userland.)
SELF="$0"
while [ -L "$SELF" ]; do
  _link="$(readlink "$SELF")"
  case "$_link" in
    /*) SELF="$_link" ;;
    *)  SELF="$(dirname "$SELF")/$_link" ;;
  esac
done
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"

# ── the ratchet: suites grandfathered as non-hermetic. ONLY EVER DELETE LINES FROM THIS LIST. ──
EMBEDDED_ALLOWLIST="$(cat <<'ALLOW'
activation-watch.bats
agent-teams-enforce.bats
anti-deference-nudge.bats
autonomy-sweep.bats
boot-resume-launch.bats
boot-resume.bats
boundary-handoff.bats
cc-announce.bats
cc-audit.bats
cc-await-ping.bats
cc-backlog.bats
cc-blockers.bats
cc-classify.bats
cc-crash-report.bats
cc-decide.bats
cc-digest.bats
cc-discover.bats
cc-dispatch.bats
cc-idl.bats
cc-inbox-guard.bats
cc-notify.bats
cc-permission-beacon.bats
cc-reaper.bats
cc-reconcile.bats
cc-recover-safeguard.bats
cc-respawn.bats
cc-route.bats
cc-run.bats
cc-teardown-safety-gate.bats
cc-teardown.bats
cc-unattended-ask-guard.bats
cc-upgrade-gate.bats
cc-wave-plan.bats
claude-accounts-core.bats
claude-accounts.bats
claude-kimi.bats
completion-assert.bats
completion-push.bats
context-econ.bats
delivery-verify.bats
deploy-parity.bats
desk-arm-live.bats
desk-assert-wiring.bats
desk-assert.bats
desk-brief-ssot.bats
desk-invariant.bats
desk-land.bats
desk-register.bats
dod-persist.bats
effort-parity.bats
exit-deadline.bats
find-plan-list-open.bats
fire-autonomy.bats
fire-engagement.bats
gate-classify.bats
gate-manifest.bats
handoff-disposition.bats
handoff-fire-account-sweep.bats
handoff-fire-completion-push.bats
handoff-fire-focus.bats
handoff-fire-inject.bats
handoff-fire-payload-lint.bats
handoff-fire-tab-window-typing.bats
handoff-fire-validate.bats
handoff-selfclose.bats
handoff-splitright.bats
idl-abstain-alarm.bats
install-wire-hooks.bats
kimi-frontend-ab.bats
land-gate-cas.bats
land-lock.bats
land-verify.bats
lead-crash-watchdog.bats
lead-deathwatch.bats
lead-supervisor.bats
lr-team-audit.bats
mail-ack-consume.bats
mailbox-drain.bats
mailbox-forward.bats
notify-back.bats
operator-readout.bats
page-damp.bats
payload-lint-tool-parity.bats
payload-lint.bats
plan-index.bats
power-policy.bats
pre-session-validate.bats
reap-guard.bats
reset-hard-shadow-allow.bats
rm-safe-allowlist.bats
rotate-autonomy-logs.bats
session-continue.bats
session-registry.bats
settings-dedup-stop.bats
ship-land.bats
ship-rail-push-allow.bats
stranded-sweep.bats
task-helpers-scope.bats
task-quality-gate.bats
validate-plan-structure.bats
wait-contract-lint.bats
waiting-recycle.bats
wrap-ledger.bats
ALLOW
)"

# ── RULE 2's ratchet: suites that exercise handoff-fire WITHOUT pinning CC_FIRE_CAPACITY_GATE=off in
# setup(). ONLY EVER DELETE LINES FROM THIS LIST. Deliberately a SECOND list and not a merge with the
# one above: the two rules are independent (a suite can be $HOME-hermetic and load-exposed, or the
# reverse), so one shared list could only shrink when BOTH were fixed — which is a ratchet that
# ratchets half as often. Derived by reading the tree, not handed down: for every tests/*.bats that
# mentions handoff-fire, the setup()/setup_file() body was checked for the pin. Four of these
# (handoff-fire-capacity-gate, handoff-fire-failed-cleanup, handoff-fire-repo-resolution,
# handoff-recycle-engagement) DO pin the gate, but per-test only — which is exactly the shape the
# rule rejects, so they are grandfathered like the rest until the pin moves into setup().
# The list was derived AGAINST TRUNK at the last possible moment, which is the only way it can be
# right: while this rule was being written, three suites (fire-engagement, handoff-fire-focus,
# handoff-fire-payload-lint) were pinned and landed by a sibling — listing them from an earlier
# reading would have shipped a ratchet that was stale on arrival, i.e. RED on its first run.
EMBEDDED_FIRE_ALLOWLIST="$(cat <<'FIREALLOW'
cc-backlog.bats
cc-classify.bats
cc-close-attrib.bats
cc-recover-safeguard.bats
cc-relogin.bats
cc-teardown.bats
cc-wave-plan-verdict.bats
cc-wave-plan.bats
claude-accounts-core.bats
claude-accounts-fresh-lock-bound.bats
desk-invariant.bats
desk-land.bats
desk-register.bats
fire-autonomy.bats
handoff-close-mail-guard.bats
handoff-fire-account-sweep.bats
handoff-fire-capacity-gate.bats
handoff-fire-completion-push.bats
handoff-fire-failed-cleanup.bats
handoff-fire-inject.bats
handoff-fire-it2-bound.bats
handoff-fire-repo-resolution.bats
handoff-fire-tab-window-typing.bats
handoff-fire-typed-cmd-correctable.bats
handoff-fire-validate.bats
handoff-lifecycle-record.bats
handoff-orphaned-assignee.bats
handoff-payload-gates.bats
handoff-recycle-durable-cwd.bats
handoff-recycle-engagement.bats
handoff-selfclose-session-pin.bats
handoff-selfclose-teammate-gate.bats
handoff-selfclose.bats
handoff-splitright.bats
handoff-teardown-marker.bats
it2-wrapper.bats
lead-crash-watchdog.bats
notify-back.bats
self-path-lint.bats
teammate-auto-shutdown.bats
waiting-recycle.bats
FIREALLOW
)"

# Rule 2's runtime knobs. Globals rather than lint_dir parameters ON PURPOSE: lint_dir's ARITY is
# load-bearing — `[ "$#" -ge 3 ]` is what separates "no own-set supplied ⇒ strict" from "own-set
# supplied but empty ⇒ nothing blocks", so a 4th positional would force every caller that wants a
# fire allowlist to also invent an own-set, silently flipping the own-scope state it never meant to
# touch. `-` not `:-` on the seam, so set-but-EMPTY legitimately means "grandfather nothing".
FIRE_ALLOW="${CC_HERM_FIRE_ALLOWLIST-$EMBEDDED_FIRE_ALLOWLIST}"
FIRE_RULE="${CC_HERM_FIRE_RULE:-on}"

# The setup()/setup_file() bodies of a suite. Terminator is a bare `}` at column 0 — the convention
# every suite in tests/ follows; the extraction was verified against all 118 before this landed.
setup_bodies() {
  awk '/^[[:space:]]*(setup|setup_file)\(\)[[:space:]]*\{/{inb=1;next}
       inb && /^\}[[:space:]]*$/{inb=0;next}
       inb{print}' "$1" 2>/dev/null
}

# ── COULD-NOT-CHECK is a THIRD state, never a verdict ─────────────────────────────────────────
# Both predicates below are `… | grep -q …`, and grep answers 0=found / 1=not-found / >1=I FAILED.
# Collapsing >1 into "not found" makes a grep that could not RUN indistinguishable from a real
# answer — so under fork pressure (a loaded box, or another session's unscoped pkill reaping this
# lint's children) the ratchet FABRICATES leaks for whichever suites were mid-check.
#
# Measured 2026-07-26 on an unchanged tree: ship-land's ratchet named cc-reconcile.bats +
# kimi-frontend-ab.bats as new leaks while both were allowlisted on that exact tree AND on trunk,
# and 3 direct runs of this same lint reported clean. Earlier the same day it produced four other
# disjoint subsets of already-allowlisted suites (rotate-autonomy-logs; cc-idl+gate-manifest+…;
# cc-crash-report+fire-engagement; find-plan-list-open+lead-crash-watchdog+rm-safe-allowlist).
#
# This is worse than a bare non-verdict because the message NAMES FILES: it reads as an
# attributable RED and sends people to "fix" suites that were never broken (it nearly cost a
# 14-file migration of other streams' tests). ship-land runs this fail-fast BEFORE bats, so one
# fabricated leak kills a land in seconds — repeatedly, and invisibly.
#
# Fix: keep 0 and 1 as answers, and make >1 set CHECK_FAILED so the run exits 2 (LOUD, unusable)
# instead of reporting a violation. Same discipline as the unusable-scan-dir path already here,
# and the repo's standing rule that gate-never-ran is not gate-red.
#
# PREDICATE RETRY. Exiting 2 is honest but still stops a land, and measured over 14 consecutive
# ship-land attempts at load 46-88 EVERY one died here — an honest non-verdict is no more landable
# than a fabricated leak. Both predicates are PURE and CHEAP (a grep over a string / a small file),
# so re-running one is free and side-effect-free, and the failure being retried is transient by
# definition. Three tries, 1s apart, before the run is condemned: that turns the common case
# (a momentarily unavailable fork) into a correct answer, and reserves CHECK_FAILED for a box
# genuinely unable to run a grep three times in a row.
CHECK_FAILED=0

# 0 = hermetic (fixtures $HOME in setup) · 1 = not · sets CHECK_FAILED if the check could not run
# shellcheck disable=SC2016  # the pattern matches the LITERAL string $BATS…; expansion would break it
is_hermetic() {
  local rc
  for _ in 1 2 3; do
    setup_bodies "$1" | grep -qE '(export[[:space:]]+HOME=|HOME="\$BATS)'; rc=$?
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  CHECK_FAILED=1
  echo "test-hermeticity-lint: ⛔ hermeticity check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 0                        # fail-SAFE: 'hermetic' cannot fabricate a LEAK
}

# ── RULE 2's two predicates. Same shape as is_hermetic(): the same 3-try retry, the same
# CHECK_FAILED third state, and a fail-SAFE direction chosen so a check that could not RUN can never
# fabricate a violation naming a good suite (the 2026-07-26 incident this file's PREDICATE RETRY
# block documents). CHECK_FAILED still forces exit 2, so fail-safe never becomes a silent green.

# Is this suite in scope for rule 2 at all? 0 = it references handoff-fire · 1 = it does not.
# Fail-SAFE = 1 (out of scope): an unreadable scope check must not pull a suite INTO the rule.
# Textual by design — a suite that reaches the fire only through some other wrapper is not matched,
# which is a known and accepted floor: the ratchet binds where the evidence is unambiguous.
references_fire() {
  local rc
  for _ in 1 2 3; do
    grep -qF 'handoff-fire' "$1" 2>/dev/null; rc=$?
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  CHECK_FAILED=1
  echo "test-hermeticity-lint: ⛔ fire-scope check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 1                        # fail-SAFE: 'not in scope' cannot fabricate an AMBIENT violation
}

# 0 = pins CC_FIRE_CAPACITY_GATE=off in setup() · 1 = does not.
# Fail-SAFE = 0 (pinned): 'pinned' cannot fabricate an AMBIENT violation. It COULD in principle
# fabricate a stuck-ratchet line for an allowlisted suite — but CHECK_FAILED makes the whole run
# exit 2 with an explicit "this is NOT a violation report", exactly as is_hermetic already does.
is_fire_pinned() {
  local rc
  for _ in 1 2 3; do
    setup_bodies "$1" | grep -qF 'CC_FIRE_CAPACITY_GATE=off'; rc=$?
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  CHECK_FAILED=1
  echo "test-hermeticity-lint: ⛔ capacity-pin check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 0                        # fail-SAFE: 'pinned' cannot fabricate an AMBIENT violation
}

# 0 = present · 1 = absent · sets CHECK_FAILED if the check could not run
in_allowlist() {
  local rc
  for _ in 1 2 3; do
    printf '%s\n' "$2" | grep -qxF "$1"; rc=$?
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1                       # transient fork pressure — see PREDICATE RETRY above
  done
  CHECK_FAILED=1
  echo "test-hermeticity-lint: ⛔ allowlist check could not RUN for $1 after 3 tries (grep rc=$rc)" >&2
  return 0                        # fail-SAFE: 'allowlisted' cannot fabricate a LEAK
}

# OWN-SCOPE (2026-07-27) — which violations may BLOCK, as distinct from which are REPORTED.
#
# WHY: the ratchet's rule is "do not ADD a leak". Enforcing it over the WHOLE tree makes every
# lander answerable for every other lander's suite, and because trunk is shared that is a
# FLEET-WIDE hard stop. Measured this session: a DOCS-ONLY land (one .md file) was refused by five
# leaking suites it does not touch — cc-close-attrib, claude-accounts-core, claude-kimi,
# completion-assert, fire-autonomy. The lander cannot fix what it did not break, so its only moves
# are "wait for someone else" or "fix five unrelated suites mid-land". One author's omission
# becomes everyone's outage; GATE_ARCHITECTURE_PLAN §9 measures the cost (66% -> 30% land rate).
#
# WHY IT IS NOW SAFE TO SCOPE. The original whole-tree fail-fast had a real premise: an unfixtured
# suite reads AND writes the operator's live ~/, contaminating every other result in the same run.
# Phase 2a (`d9b934ee`, per-gate $HOME isolation via APFS clonefile) removed that premise — the
# gate's bats children run under a CLONED $HOME, so a leak now dirties the clone, not the operator.
# That argument was load-bearing until 2a landed, and is not after. This change is therefore a
# COMPOSITION with 2a, not a weakening of the ratchet.
#
# WHAT DOES NOT CHANGE: the full tree is still scanned and every violation still printed — a leak
# outside the set is LABELLED, never hidden, so "advisory" can never be misread as "clean". Only
# the EXIT CODE narrows. With no own-set the behaviour is byte-identical to before (every violation
# blocks), so --selftest, the postland net, and a bare human invocation are untouched. ship-land is
# the sole opt-in caller. Kill switch: SHIP_LAND_HERM_OWN_SCOPE=off restores whole-tree blocking.
# THREE states, not two — and `${VAR:-}` cannot express them, which is the bug this comment exists
# to prevent recurring. An own-set that is ABSENT means "strict, judge the whole tree" (postland, a
# bare human run). An own-set that is PRESENT BUT EMPTY means "this land changes no suite at all",
# so NOTHING may block — the docs-only land that motivated the fix. Collapsing them with `${3:-}`
# reinstates the exact hard stop being removed, silently and only for the docs-only case. Presence
# is therefore carried by ARGUMENT COUNT here and by `${CC_HERM_OWN+set}` at the entrypoint.
in_own() {  # $1=basename · $2=own-set text · $3=1 if an own-set was supplied at all
  [ "${3:-0}" = "1" ] || return 0          # no own-set supplied ⇒ everything is own ⇒ strict
  [ -n "$2" ] || return 1                  # supplied but empty ⇒ nothing is own ⇒ nothing blocks
  printf '%s\n' "$2" | sed 's:.*/::' | grep -qxF "$1"
}

# lint <tests-dir> <allowlist-text> [own-set-text] — 0 clean · 1 violations · 2 unusable scan dir
lint_dir() {
  local dir="$1" allow="$2" own="${3:-}" own_scoped=0 f base new_leak=0 stuck=0 seen=0 other=0
  local fire_allow="$FIRE_ALLOW" fire_leak=0 fire_stuck=0
  [ "$#" -ge 3 ] && own_scoped=1
  CHECK_FAILED=0
  [ -d "$dir" ] || { echo "test-hermeticity-lint: ⛔ not a directory: $dir" >&2; return 2; }
  for f in "$dir"/*.bats; do
    [ -e "$f" ] || continue
    seen=$((seen + 1)); base="$(basename "$f")"
    if is_hermetic "$f"; then
      if in_allowlist "$base" "$allow"; then
        if in_own "$base" "$own" "$own_scoped"; then
          printf '  RATCHET  %s is hermetic now — delete its allowlist line\n' "$base"
          stuck=$((stuck + 1))
        else
          printf '  ratchet? %s is hermetic but still grandfathered (NOT in your diff — advisory)\n' "$base"
          other=$((other + 1))
        fi
      fi
    elif ! in_allowlist "$base" "$allow"; then
      if in_own "$base" "$own" "$own_scoped"; then
        # shellcheck disable=SC2016  # "$HOME" is prose here — the message names the variable, not its value
        printf '  LEAK     %s: setup() does not fixture $HOME — it runs against the live ~/\n' "$base"
        new_leak=$((new_leak + 1))
      else
        # shellcheck disable=SC2016  # ditto — prose naming the variable, not an expansion
        printf '  leak?    %s does not fixture $HOME (NOT in your diff — advisory, not blocking)\n' "$base"
        other=$((other + 1))
      fi
    fi
    # ── RULE 2, applied INDEPENDENTLY of rule 1 (a suite can violate either, both, or neither) and
    # ONLY to suites that reference handoff-fire. A suite that never touches the fire is out of
    # scope and must never appear here — that scoping is the whole reason references_fire() exists.
    if [ "$FIRE_RULE" = on ] && references_fire "$f"; then
      if is_fire_pinned "$f"; then
        if in_allowlist "$base" "$fire_allow"; then
          if in_own "$base" "$own" "$own_scoped"; then
            printf '  RATCHET-CAP  %s pins the capacity gate now — delete its FIRE allowlist line\n' "$base"
            fire_stuck=$((fire_stuck + 1))
          else
            printf '  ratchet-cap? %s pins the gate but is still grandfathered (NOT in your diff — advisory)\n' "$base"
            other=$((other + 1))
          fi
        fi
      elif ! in_allowlist "$base" "$fire_allow"; then
        if in_own "$base" "$own" "$own_scoped"; then
          printf '  AMBIENT  %s: setup() does not pin CC_FIRE_CAPACITY_GATE=off — its fires read live machine load\n' "$base"
          fire_leak=$((fire_leak + 1))
        else
          printf '  ambient? %s does not pin CC_FIRE_CAPACITY_GATE=off (NOT in your diff — advisory, not blocking)\n' "$base"
          other=$((other + 1))
        fi
      fi
    fi
  done
  [ "$seen" -gt 0 ] || { echo "test-hermeticity-lint: ⛔ no .bats suites under $dir" >&2; return 2; }
  [ "$other" -eq 0 ] || echo "test-hermeticity-lint: $other pre-existing violation(s) NOT in your diff — reported, not blocking (own-scope)."
  # A run whose own predicates could not execute has no verdict to give. Exit 2 (unusable), the
  # same code as a bad scan dir — NOT 1, which a caller reads as "your tree is dirty". Checked
  # AFTER the own-scope report so a killed predicate cannot masquerade as a clean own-scope pass:
  # own-scope narrows WHICH violations block, it does not make an unrunnable check trustworthy.
  if [ "$CHECK_FAILED" -ne 0 ]; then
    echo "test-hermeticity-lint: ⛔ UNUSABLE — a predicate failed to run (see above); no verdict." >&2
    echo "  This is NOT a leak report. Re-run when the box is quieter; do not 'fix' any suite on it." >&2
    return 2
  fi

  if [ "$new_leak" -gt 0 ]; then
    echo "test-hermeticity-lint: ⛔ $new_leak new non-hermetic suite(s) above."
    echo "  Fix: in setup(), \`export HOME=\"\$BATS_TEST_TMPDIR/home\"; mkdir -p \"\$HOME\"\`, then"
    echo "       seed whatever fixture state the subject reads under it. Do NOT add to the allowlist."
  fi
  if [ "$stuck" -gt 0 ]; then
    echo "test-hermeticity-lint: ⛔ $stuck suite(s) above are fixed but still grandfathered."
    echo "  Fix: delete their lines from EMBEDDED_ALLOWLIST in $0 — the ratchet only shrinks."
  fi
  if [ "$fire_leak" -gt 0 ]; then
    echo "test-hermeticity-lint: ⛔ $fire_leak suite(s) above exercise handoff-fire against AMBIENT machine load."
    echo "  WHY: handoff-fire's capacity_gate() refuses a net-new fire above ${CC_FIRE_MAX_LOAD_PER_CORE:-2.0}/core"
    echo "       and this box lives well above that, so the suite goes red-by-load, not by its subject."
    echo "  Fix: in setup(), \`export CC_FIRE_CAPACITY_GATE=off\`. Do NOT add to the fire allowlist."
  fi
  if [ "$fire_stuck" -gt 0 ]; then
    echo "test-hermeticity-lint: ⛔ $fire_stuck suite(s) above pin the capacity gate but are still grandfathered."
    echo "  Fix: delete their lines from EMBEDDED_FIRE_ALLOWLIST in $0 — the ratchet only shrinks."
  fi
  [ $((new_leak + stuck + fire_leak + fire_stuck)) -eq 0 ] || return 1
  # The summary must say what was ENFORCED, not what is merely on disk: with rule 2 killed, printing
  # its grandfather count would read as "43 suites checked and grandfathered" when zero were checked.
  local fire_note
  if [ "$FIRE_RULE" = on ]; then
    fire_note="$(printf '%s\n' "$fire_allow" | grep -c .) grandfathered (capacity gate)"
  else
    fire_note="capacity-gate rule OFF (CC_HERM_FIRE_RULE)"
  fi
  echo "test-hermeticity-lint: clean — $seen suite(s); $(printf '%s\n' "$allow" | grep -c .) grandfathered (\$HOME), $fire_note, 0 new leaks."
  return 0
}

# ── --selftest: PROVE both RED paths fire and both GREEN paths don't (harness law: every assertion
# traps). Case (e) lints the REAL tree with the REAL allowlist, so a stale ratchet is caught here too.
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  mkdir -p "$d/leak" "$d/herm"
  cat >"$d/leak/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}
@test "x" { true; }
F
  cat >"$d/herm/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
}
@test "x" { true; }
F
  # ── RULE 2 fixtures. All four are $HOME-hermetic on purpose, so a rule-2 verdict can never be
  # rule 1 leaking through: the ONLY axis that varies is the handoff-fire reference and the pin.
  # nofire is byte-identical to fireleak MINUS the reference — the scope control for case (r).
  mkdir -p "$d/nofire" "$d/fireleak" "$d/firepin" "$d/firepertest"
  cat >"$d/nofire/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  SUBJECT="$REPO/scripts/some-other-tool.sh"
}
@test "x" { run bash "$SUBJECT" --dry-run; }
F
  cat >"$d/fireleak/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  SUBJECT="$REPO/scripts/handoff-fire.sh"
}
@test "x" { run bash "$SUBJECT" --dry-run; }
F
  cat >"$d/firepin/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off
  SUBJECT="$REPO/scripts/handoff-fire.sh"
}
@test "x" { run bash "$SUBJECT" --dry-run; }
F
  cat >"$d/firepertest/zz-fixture.bats" <<'F'
#!/usr/bin/env bats
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  SUBJECT="$REPO/scripts/handoff-fire.sh"
}
@test "a" { CC_FIRE_CAPACITY_GATE=off run bash "$SUBJECT" --dry-run; }
@test "b" { run bash "$SUBJECT" --dry-run; }
F
  fails=0
  # Pin BOTH rule-2 knobs for the duration of the selftest: an ambient CC_HERM_FIRE_RULE=off or a
  # stray CC_HERM_FIRE_ALLOWLIST in the caller's environment would otherwise make every rule-2
  # assertion below pass VACUOUSLY, which is the one way a discrimination proof can lie.
  FIRE_RULE=on
  FIRE_ALLOW=""
  lint_dir "$d/leak" ""               >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a NEW non-hermetic suite did not go RED"; fails=1; }
  lint_dir "$d/herm" "zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a fixed-but-still-allowlisted suite did not go RED (ratchet not shrinking)"; fails=1; }
  lint_dir "$d/herm" ""                >/dev/null 2>&1 || { echo "SELFTEST FAIL: a hermetic suite did not go GREEN"; fails=1; }
  lint_dir "$d/leak" "zz-fixture.bats"  >/dev/null 2>&1 || { echo "SELFTEST FAIL: a grandfathered suite did not go GREEN"; fails=1; }
  # Case (e) must tell its two failure codes APART. A stale allowlist is a VERDICT about the tree
  # (exit 1). An unscannable dir is a NON-VERDICT (exit 2) and says nothing whatever about the
  # allowlist. Collapsing them is how the ROOT bug above surfaced as "your ratchet is stale" —
  # the same verdict/non-verdict conflation ship-land keeps apart as gate-red 6 vs gate-killed 9.
  # Both embedded allowlists are judged here, so a stale entry in EITHER ratchet is caught by (e).
  FIRE_ALLOW="$EMBEDDED_FIRE_ALLOWLIST"
  lint_dir "$ROOT/tests" "$EMBEDDED_ALLOWLIST" >/dev/null 2>&1; rc_real=$?
  FIRE_ALLOW=""
  case "$rc_real" in
    0) ;;
    2) echo "SELFTEST FAIL: could not scan $ROOT/tests — a NON-VERDICT (bad ROOT?), NOT a stale allowlist"; fails=1 ;;
    *) echo "SELFTEST FAIL: an embedded allowlist is stale (\$HOME and/or capacity-gate) — the real tree is not clean"; fails=1 ;;
  esac
  lint_dir "$d/nope" ""               >/dev/null 2>&1; [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: a missing scan dir did not exit 2 (LOUD)"; fails=1; }
  # ── OWN-SCOPE: both directions, because a scope that can only PASS is not a scope ────────────
  # (g) a leak OUTSIDE the own-set must not block — the fleet-wide-hard-stop fix itself.
  lint_dir "$d/leak" "" "some-other-suite.bats" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a leak OUTSIDE the own-set blocked (own-scope not applied)"; fails=1; }
  # (h) the SAME leak INSIDE the own-set must still block — proves (g) passed for the right reason
  #     and not because own-scope simply disables the rule.
  lint_dir "$d/leak" "" "zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a leak INSIDE the own-set did not block — own-scope disabled the ratchet"; fails=1; }
  # (i) a stuck ratchet entry outside the own-set is advisory; inside it still blocks.
  lint_dir "$d/herm" "zz-fixture.bats" "other.bats" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a stuck entry OUTSIDE the own-set blocked"; fails=1; }
  lint_dir "$d/herm" "zz-fixture.bats" "zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a stuck entry INSIDE the own-set did not block"; fails=1; }
  # (j) an own-set given as a PATH must match by basename — ship-land passes `tests/x.bats`.
  lint_dir "$d/leak" "" "tests/zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: own-set given as a path did not match by basename"; fails=1; }
  # (k) THE DOCS-ONLY CASE — an own-set SUPPLIED BUT EMPTY means "I change no suite": nothing may
  #     block. This is the whole point of the fix and the one `${VAR:-}` would silently break.
  lint_dir "$d/leak" "" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: an EMPTY own-set blocked — set-empty was collapsed into unset, docs-only lands still hard-stop"; fails=1; }
  # (l) …while omitting the argument entirely still means STRICT. (k) and (l) differ ONLY in arity,
  #     so together they prove the three states are really distinguished.
  lint_dir "$d/leak" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an ABSENT own-set did not block — strict default lost"; fails=1; }
  # (m) entrypoint-level parity for the same distinction, via the real CC_HERM_OWN seam.
  ( unset CC_HERM_OWN; CC_HERM_ALLOWLIST="" "$SELF" "$d/leak" >/dev/null 2>&1 ); [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: CC_HERM_OWN unset did not block at the entrypoint"; fails=1; }
  ( CC_HERM_OWN="" CC_HERM_ALLOWLIST="" "$SELF" "$d/leak" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: CC_HERM_OWN set-but-empty blocked at the entrypoint"; fails=1; }
  # (n) COULD-NOT-CHECK is a non-verdict, not a leak — and own-scope must not paper over it.
  # Simulates the real incident: a `grep` that cannot RUN (rc>1). Shadowing grep in a subshell
  # reproduces exactly what fork exhaustion / a reaped child does to these predicates. Before the
  # fix this reported a LEAK naming a perfectly good suite; the contract is exit 2 and no leak line.
  ( grep() { return 2; }
    out="$(lint_dir "$d/leak" "" 2>&1)"; rc=$?
    [ "$rc" -eq 2 ] || { echo "SELFTEST FAIL: an unrunnable predicate did not exit 2 (got $rc) — a killed check must never be a verdict"; exit 1; }
    printf '%s' "$out" | grep -q 'LEAK' && { echo "SELFTEST FAIL: an unrunnable predicate still fabricated a LEAK line"; exit 1; }
    exit 0
  ) || fails=1
  # (o) …and it stays a non-verdict WITH an own-set supplied: own-scope narrows which violations
  # BLOCK, it never makes an unrunnable check trustworthy. Guards the composition of the two fixes.
  ( grep() { return 2; }
    lint_dir "$d/leak" "" "zz-fixture.bats" >/dev/null 2>&1
    [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: an unrunnable predicate under own-scope did not exit 2"; exit 1; }
    exit 0
  ) || fails=1

  # ── RULE 2 (capacity gate) — the same two-sided discipline, plus a SCOPE control, because a rule
  # that fires on everything would pass every RED assertion below while being worthless. ──────────
  # (p) RED: a suite that drives handoff-fire without pinning the gate reads AMBIENT machine load.
  lint_dir "$d/fireleak" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an UNPINNED handoff-fire suite did not go RED (rule 2 is inert)"; fails=1; }
  # (q) GREEN: the same suite with the pin in setup() — the fix the RED prescribes actually clears it.
  lint_dir "$d/firepin" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a suite pinning CC_FIRE_CAPACITY_GATE=off in setup() did not go GREEN"; fails=1; }
  # (r) SCOPE CONTROL for (p): the same suite MINUS the handoff-fire reference must be GREEN. Without
  #     this, (p) could be passing because rule 2 flags every suite, not because that suite fires.
  lint_dir "$d/nofire" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a suite that never mentions handoff-fire was flagged — rule 2 is not scoped"; fails=1; }
  # (s) RED: pinned but STILL on the fire allowlist — the second ratchet may only ever shrink.
  FIRE_ALLOW="zz-fixture.bats"
  lint_dir "$d/firepin" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a pinned-but-still-grandfathered suite did not go RED (fire ratchet is not shrinking)"; fails=1; }
  # (t) GREEN: unpinned but grandfathered — today's list must not block anybody. Pairs with (s):
  #     together they show the fire allowlist is consulted in BOTH directions, not just one.
  lint_dir "$d/fireleak" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a grandfathered unpinned suite did not go GREEN"; fails=1; }
  FIRE_ALLOW=""
  # (u) per-TEST pinning does NOT count — rule 1's reason verbatim: every OTHER test in the file is
  #     still on ambient load. Four suites in the tree are grandfathered for exactly this shape.
  lint_dir "$d/firepertest" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a per-TEST CC_FIRE_CAPACITY_GATE counted as pinned"; fails=1; }
  # (w) own-scope governs rule 2 as well: advisory OUTSIDE the lander's diff, blocking INSIDE it.
  lint_dir "$d/fireleak" "" "some-other-suite.bats" >/dev/null 2>&1 || { echo "SELFTEST FAIL: an AMBIENT violation OUTSIDE the own-set blocked"; fails=1; }
  lint_dir "$d/fireleak" "" "zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an AMBIENT violation INSIDE the own-set did not block"; fails=1; }
  # (x) COULD-NOT-CHECK survives rule 2: an unrunnable predicate is a NON-VERDICT (exit 2) and must
  #     never print an AMBIENT line naming a suite nobody was able to check. The output test is a
  #     `case`, not a grep — grep is the very thing stubbed here, so a grep-based assertion would be
  #     structurally incapable of failing (a dead assertion wearing an assertion's clothes).
  ( grep() { return 2; }
    out="$(lint_dir "$d/fireleak" "" 2>&1)"; rc=$?
    [ "$rc" -eq 2 ] || { echo "SELFTEST FAIL: an unrunnable rule-2 predicate did not exit 2 (got $rc)"; exit 1; }
    case "$out" in *AMBIENT*) echo "SELFTEST FAIL: an unrunnable rule-2 predicate still fabricated an AMBIENT line"; exit 1 ;; esac
    exit 0
  ) || fails=1
  # (y) entrypoint parity for the CC_HERM_FIRE_ALLOWLIST seam, both directions — the RED half is
  #     also the positive control for the kill switch in (z), which is the identical command + one
  #     variable. Rule 1's allowlist is emptied in both so only rule 2 can produce the verdict.
  #     CC_HERM_FIRE_RULE=on is passed explicitly so an ambient kill switch in the CALLER's
  #     environment cannot neuter the child and turn (y)'s RED half into an unexplained failure.
  ( CC_HERM_ALLOWLIST="" CC_HERM_FIRE_ALLOWLIST="" CC_HERM_FIRE_RULE=on "$SELF" "$d/fireleak" >/dev/null 2>&1 ); [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: CC_HERM_FIRE_ALLOWLIST set-but-empty did not block at the entrypoint"; fails=1; }
  ( CC_HERM_ALLOWLIST="" CC_HERM_FIRE_ALLOWLIST="zz-fixture.bats" CC_HERM_FIRE_RULE=on "$SELF" "$d/fireleak" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: CC_HERM_FIRE_ALLOWLIST did not grandfather at the entrypoint"; fails=1; }
  # (z) the kill switch turns rule 2 off — and ONLY rule 2 (rule 1 still judges the same tree).
  ( CC_HERM_ALLOWLIST="" CC_HERM_FIRE_ALLOWLIST="" CC_HERM_FIRE_RULE=off "$SELF" "$d/fireleak" >/dev/null 2>&1 ) || { echo "SELFTEST FAIL: CC_HERM_FIRE_RULE=off did not disable rule 2"; fails=1; }

  if [ "$fails" -eq 0 ]; then
    echo "test-hermeticity-lint --selftest: 29/29 — RULE 1 (\$HOME): RED on a new leak + on a stuck ratchet entry, GREEN on hermetic + grandfathered, GREEN on the real tree, LOUD on a bad dir, own-scope blocks INSIDE / advises OUTSIDE for both violation kinds (path-form accepted), NON-VERDICT on an unrunnable check (with and without an own-set). RULE 2 (capacity gate): RED on an unpinned handoff-fire suite + on a per-test pin + on a stuck fire-ratchet entry, GREEN on a setup()-pinned suite + on a grandfathered one + on a suite that never mentions handoff-fire (the scope control), own-scope honoured both ways, NON-VERDICT on an unrunnable fire predicate, and both env seams (CC_HERM_FIRE_ALLOWLIST, CC_HERM_FIRE_RULE=off) proved at the entrypoint."
    exit 0
  fi
  echo "test-hermeticity-lint --selftest: FAILED — the ratchet does not discriminate."
  exit 1
fi

# CC_HERM_OWN — newline-delimited suite names (basenames or paths) the caller is answerable for.
# UNSET ⇒ strict whole-tree blocking, exactly as before. SET (including set to EMPTY) ⇒ own-scope,
# where an empty value legitimately means "I change no suite, so nothing may block me". `+set` is
# the only test that separates those; `${CC_HERM_OWN:-}` would collapse them and silently reinstate
# the hard stop for precisely the docs-only land this fixes.
if [ -n "${CC_HERM_OWN+set}" ]; then
  lint_dir "${1:-$ROOT/tests}" "${CC_HERM_ALLOWLIST-$EMBEDDED_ALLOWLIST}" "$CC_HERM_OWN"
else
  lint_dir "${1:-$ROOT/tests}" "${CC_HERM_ALLOWLIST-$EMBEDDED_ALLOWLIST}"
fi
exit $?
