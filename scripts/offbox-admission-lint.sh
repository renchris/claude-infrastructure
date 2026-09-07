#!/bin/bash
# offbox-admission-lint — the ADMISSION GATE for the hermetic partition.
#
#   offbox-admission-lint.sh [--range <git-range>] [--working] [tests-dir]
#   offbox-admission-lint.sh --added tests/a.bats[,tests/b.bats]     explicit set (tests + callers)
#   offbox-admission-lint.sh --selftest
#
# Exit 0 admit · 1 refuse (a suite this change ADDS is not off-box-clean) · 2 unusable (no runner).
#
# ── THE DEFECT THIS CLOSES, STATED AS A RULE ─────────────────────────────────────────────────────
# `scripts/offbox-partition.sh` computes the partition as a SET DIFFERENCE, so **a suite enters the
# hermetic partition BY EXISTING**, not by being proven off-box-clean. That direction is correct and
# must not be reversed — an INCLUSION list decays invisibly, which that file argues at length and
# this one does not relitigate. But it has a consequence its own header states and prices as one
# red: *"a genuinely machine-coupled new suite reds the off-box run on the land that adds it. That
# is the intended bill."*
#
# THE BILL HAS NO ADDRESSEE, AND THAT IS THE ACTUAL GENERATOR. The red lands an hour later, in a
# GitHub step summary, naming a suite but not a person, and it does not block the land that caused
# it (by construction — hermetic.yml never gates /ship). Meanwhile ONE not-green suite makes the
# workflow's binary conclusion non-green, no off-box stamp is written, and `deploy-live.sh`'s T1H
# tier — the ONLY tier that advances on a positive result with no lag budget — is shut FOR THE WHOLE
# MACHINE. So the cost of adding a non-hermetic suite is paid by everyone and owed by nobody: the
# textbook unowned-shared-resource shape, in which the growth side is mechanized and the cure side
# is a human reading a summary.
#
# MEASURED 2026-08-12, three folds in one day, which is why this exists rather than a whack-a-mole:
#   11:56Z  405 suites  403 green  2 red      autonomy-sweep · worker-claim-gate-coverage
#   12:58Z  408 suites  406 green  1 red + 1 nonverdict
#   22:01Z  414 suites  411 green  3 red      boundary-handoff · land-gate-cas · typed-send-lint
# Two suites were fixed and STAYED fixed, and the red count still rose, because the corpus grew by 9.
# Fixing today's three does nothing about tomorrow's; only moving the cost to the author does.
#
# ── WHAT IT DOES: MOVE THE BILL TO THE AUTHOR, AT THE MOMENT OF THE ACT ──────────────────────────
# A suite this change ADDS, and which lands INSIDE the partition, must be green under the off-box
# runner before it may land. Not green ⇒ the land is refused and the author gets the cure. The rule
# binds only where it is free — NEW suites — exactly the ratchet contract of its five sibling arms
# (test-hermeticity-lint, test-walltime-lint, git-identity-lint, subshell-cleanup-lint,
# test-afunix-path-lint). An EXISTING suite is never re-run by this gate: it is already in the
# partition and already measured hourly, so re-running it would spend the author's wall-clock to
# re-derive something the producer already knows.
#
# ── IT RUNS THE PRODUCER'S OWN RUNNER — IT DOES NOT EMULATE ONE ──────────────────────────────────
# The check is `offbox-run.sh suites <suite>`, which reaches the SAME `run_one` the CI shards use:
#   env -i HOME=<fresh empty> TMPDIR=<fresh> PATH TERM=dumb LC_ALL=C CC_OFFBOX=1 timeout -k 10 300 bats
# A gate that REFUSES a land must run the same predicate the producer runs, or it refuses on a claim
# it cannot substantiate — and a hand-rolled `env -i` line is the second implementation that drifts
# on the first edit nobody makes twice (memory: make-the-actuator-the-arbiter — never re-implement
# an atomic gate's predicate).
#
# POSITIVE CONTROL, measured 2026-08-12 before this file was written, because a gate whose probe
# cannot fail is the vacuous pass this repo has paid for repeatedly:
#   `bats tests/boundary-handoff.bats`                        → 35/35 GREEN   (ordinary, on-box)
#   `offbox-run.sh suites tests/boundary-handoff.bats`        → red ok=34 notok=1, 27s
# set-identical to that day's off-box fold. So this probe reproduces a real off-box red on the box
# that has to fix it, deterministically, in seconds — it is not an emulation whose fidelity is a
# hypothesis. tests/offbox-admission-lint.bats pins that two-sidedness as a control.
#
# ── THE HONEST LIMIT: WHAT THIS GATE STRUCTURALLY CANNOT SEE ─────────────────────────────────────
# It runs on THIS box. It therefore reproduces the environment axes (empty $HOME, no ~/.gitconfig,
# `env -i`, LC_ALL=C, TERM=dumb, a fresh TMPDIR) and NOT the machine axes: a hosted runner also has
# no iTerm2, no loaded launchd agents, a different scheduler band, and a different brew prefix. A
# suite that reds off-box for one of THOSE reasons passes here and still shuts the door. That class
# is precisely what `scripts/offbox-excluded.manifest` is for, and it is why this gate is one half of
# the fix and the manifest's shrink arm is the other. Stating the limit is not a caveat — a gate
# that claimed to cover the machine axes would send authors hunting for a defect on the wrong axis.
#
# ── THE GATE ALLOWS ITS OWN CURE, WHICH IS WHAT MAKES IT LANDABLE ────────────────────────────────
# Two cures, both one line, both landing in the SAME commit as the suite:
#   (a) fix the suite so it is off-box-clean; or
#   (b) add it to `scripts/offbox-excluded.manifest` — which removes it from the partition, so this
#       gate then skips it and the land proceeds.
# (b) is not an escape hatch that costs nothing. That manifest's contract is that EVERY ENTRY IS A
# MEASUREMENT, and this gate hands the author the measurement it just took, paste-ready, in the
# refusal. Before this existed the only source of that measurement was a CI round-trip, so the
# contract was satisfiable only by waiting an hour — which is a large part of why the list was
# curated by hand and rarely at all. A gate that could not be satisfied would be routed around
# (memory: work-item-remedy-can-become-forbidden — a gate that prints a Fix it rejects).
#
# ── RATCHET DIRECTION: THIS ARM ALSO SHRINKS THE LIST ────────────────────────────────────────────
# An exclusion nothing ever re-tests is a permanent hole. `offbox-run.sh census` is the re-measuring
# arm the manifest's header promises, but it is a `workflow_dispatch` checkbox — no schedule, no
# consumer, and nothing that deletes a line. So the list could only ever grow. Two things change
# that: `.github/workflows/hermetic.yml` now runs the census on a daily cron (the untouched-suite
# half), and the RATCHET arm below re-measures any EXCLUDED suite that THIS change modifies and
# reports it as a stuck entry when it now passes (the touched-suite half) — the same "fixed but
# still grandfathered is RED" law every sibling ratchet in this tree enforces.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
while [ -L "$SELF" ]; do SELF="$(cd "$(dirname "$SELF")" && cd "$(dirname "$(readlink "$SELF")")" && pwd)/$(basename "$(readlink "$SELF")")"; done

# Seams, all for the selftest and for the land gate. Each is a SEPARATE binary so a caller can stub
# the expensive half (the runner) without also stubbing the cheap half (the partition).
#
# 🚨 READ AT CALL TIME, NOT LOAD TIME. As globals these were assigned before `--selftest` exported
# its stubs, so every case silently ran against the REAL partition and the REAL runner: S1/S3/S6
# "passed" by admitting suites that do not exist in the real partition, i.e. the gate's own controls
# were VACUOUS in the refusing direction. `scripts/test-walltime-lint.sh` states this law verbatim
# for `horizon_years()` — *"a load-time global cannot be overridden by an env prefix on the function,
# which made the horizon inert and its own selftest case vacuous — caught by that case."* Caught by
# that case here too, which is the only reason these are functions.
runner_bin()    { printf '%s' "${CC_OFFBOX_ADM_RUNNER:-$(dirname "$SELF")/offbox-run.sh}"; }
partition_bin() { printf '%s' "${CC_OFFBOX_ADM_PARTITION:-$(dirname "$SELF")/offbox-partition.sh}"; }
root_dir()      { printf '%s' "${CC_OFFBOX_ADM_ROOT:-$(cd "$(dirname "$SELF")/.." && pwd)}"; }
TRUNK="${CC_OFFBOX_ADM_TRUNK:-main}"

die() { printf 'offbox-admission-lint: %s\n' "$1" >&2; exit "${2:-1}"; }

usage() { sed -n '2,/^set -uo/p' "$SELF" | sed 's/^# \{0,1\}//; /^set -uo/d'; }

# ── the two suite sets ───────────────────────────────────────────────────────────────────────────
# partition_has / excluded_has — asked of offbox-partition.sh, never re-derived here. A second
# implementation of "is this suite in the partition" is the drift this whole lane keeps paying for,
# and the set difference is that script's ONE job.
# DRAINED (`grep -xF … >/dev/null`), never `grep -qxF`: each of these is a functions LAST command, so
# its rc is the return value read at :201 (`if ! partition_has`) and :231 (`excluded_has … ||
# continue`). A `-q` consumer exits on its match and SIGPIPEs the producer, and pipefail promotes the
# 141 — a suite that IS in the partition would read as absent, which is this gates whole verdict.
partition_has() { printf '%s\n' "$1" | grep -xF -f <(bash "$(partition_bin)" list 2>/dev/null) >/dev/null 2>&1; }
excluded_has()  { printf '%s\n' "$1" | grep -xF -f <(bash "$(partition_bin)" excluded 2>/dev/null) >/dev/null 2>&1; }

# ADDED suites in a range. `--diff-filter=A` is the whole rule: this gate binds on ENTRY to the
# partition, and only an added file enters it.
#
# 🚨 UNTRACKED FILES ARE INVISIBLE TO `git diff` (memory: gate-scope-from-git-diff-is-blind-to-
# untracked — a pre-check cleared a tree the land then REFUSED, because the new file was in no
# own-set). A land gates committed work, so the range form is right there; but `--working` exists
# for ship-land's --precheck --working mode, and in THAT mode an unstaged new suite is exactly the
# thing being gated. So --working unions the range with untracked tests/*.bats.
added_in_range() { # $1=range
  ( cd "$(root_dir)" && git diff --diff-filter=A --name-only "$1" -- 'tests/*.bats' 2>/dev/null )
}
untracked_suites() {
  ( cd "$(root_dir)" && git ls-files --others --exclude-standard -- 'tests/*.bats' 2>/dev/null )
}
# MODIFIED (not added) suites — the input to the shrink arm only.
modified_in_range() { # $1=range
  ( cd "$(root_dir)" && git diff --diff-filter=M --name-only "$1" -- 'tests/*.bats' 2>/dev/null )
}

# run_suite <suite> — echoes the runner's TSV state word (green|red|cut|empty|missing), or `unusable`
# when the runner itself could not speak. Distinguishing those two is the whole R6 discipline: a
# runner that cannot run is a NON-VERDICT about the machine, never a verdict about the suite, and
# convicting an author on it is how a gate earns a reputation for lying.
run_suite() {
  local suite="$1" tsv rc
  # CC_OFFBOX_ROOT is passed EXPLICITLY so the runner resolves suites against the tree THIS gate is
  # gating. Without it the runner falls back to its own script-relative root, so a lint pointed at
  # one tree would silently run another's suites — harmless while both are the repo, and a vacuous
  # pass the moment anything (a test fixture, a worktree, a --range on a detached checkout) makes
  # them differ. The two roots are one fact; passing it is what keeps them from becoming two.
  tsv="$(CC_OFFBOX_ROOT="$(root_dir)" bash "$(runner_bin)" suites "$suite" 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 2 ]; then printf 'unusable\n'; return 0; fi
  # The TSV carries a header line plus one row; take the row for THIS suite by name, never by
  # position — a runner that grows a column or a warning line must not silently reclassify.
  printf '%s\n' "$tsv" | awk -F'\t' -v s="$suite" '$1 == s { print $2; found=1 } END { if (!found) print "unusable" }' | head -1
}

# ── the refusal, which is also the cure ──────────────────────────────────────────────────────────
cure_block() { # $1=suite $2=state
  printf '\n  ── cure (pick ONE, in the SAME commit as the suite) ──────────────────────────────\n'
  printf '  (a) FIX IT. Reproduce in seconds, on this box, with the identical runner CI uses:\n'
  printf '        bash scripts/offbox-run.sh suites %s\n' "$1"
  printf '      The axes that differ from your shell, in likely-culprit order: LC_ALL=C (character\n'
  printf '      ops become BYTE ops) · env -i (every unnamed variable is GONE) · a FRESH EMPTY HOME\n'
  printf '      (no ~/.gitconfig, so init.defaultBranch is unset; no ~/.claude) · TERM=dumb.\n'
  printf '  (b) EXCLUDE IT, if the suite is genuinely machine-coupled (needs iTerm2, launchd,\n'
  printf '      sysctl, the real box). Paste into scripts/offbox-excluded.manifest — the line\n'
  printf '      already carries the measurement that file requires of every entry:\n\n'
  printf '        # %s: off-box state=%s (offbox-admission-lint, at land)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$2"
  printf '        %s\n\n' "$1"
  printf '      Excluding is not free: it is coverage this producer then never has. Prefer (a).\n'
}

# ── lint <range> <added-override> <working> ──────────────────────────────────────────────────────
# 0 admit · 1 refuse · 2 unusable.
lint_range() {
  local range="$1" added_override="$2" working="${3:-0}" added_supplied="${4:-0}"
  local added="" modified="" s state refused=0 checked=0 skipped=0 stuck=0 unusable=0

  # THREE STATES ON THE ADDED-SET SEAM, not two — the same law every manifest seam in this lane
  # already carries (offbox-partition.sh § THREE STATES, test-hermeticity-lint.sh:1280). ABSENT ⇒
  # derive the set from the range. SET-BUT-EMPTY ⇒ "this change adds no suite", which must ADMIT and
  # is a real position a caller takes — a docs-only land is exactly it. `[ -n "$x" ]` collapses those
  # two, and the collapse is not cosmetic: with the range branch reached on an empty override this
  # returned 2 (unusable) for a change that adds nothing, i.e. the commonest land in the tree would
  # have been reported as a broken gate. Caught by S7.
  if [ "$added_supplied" = "1" ]; then
    # `tr ', ' '\n'` — SET2 shorter than SET1 is fine and is the point: tr pads SET2 with its last
    # character, so BOTH the comma and the space map to a newline. Spelling it '\n\n' to make the
    # pairing visual duplicates a character in SET2, which is SC2020, and the gate runs shellcheck at
    # info severity where a local `-S warning` sweep does not see it.
    added="$(printf '%s\n' "$added_override" | tr ', ' '\n' | awk 'NF')"
  else
    [ -n "$range" ] || return 2
    added="$(added_in_range "$range")"
    [ "$working" = "1" ] && added="$(printf '%s\n%s\n' "$added" "$(untracked_suites)" | awk 'NF' | sort -u)"
    modified="$(modified_in_range "$range")"
  fi

  # ── ADMISSION ARM ──────────────────────────────────────────────────────────────────────────────
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    if ! partition_has "$s"; then
      # Out of the partition by host-coupling or by an existing exclusion — nothing to admit. Say so
      # rather than staying silent: an author who just added a manifest line needs to see it took.
      printf '  skip     %s — not in the hermetic partition (host-coupled or already excluded)\n' "$s"
      skipped=$((skipped + 1)); continue
    fi
    checked=$((checked + 1))
    state="$(run_suite "$s")"
    case "$state" in
      green)
        printf '  admit    %s — green off-box\n' "$s" ;;
      unusable|missing)
        # NEVER a refusal. The runner could not speak; that is a claim about this machine, not about
        # the author's suite (LAND_PIPELINE_V2 R6 — a non-verdict is never a red).
        printf '  ABSTAIN  %s — the off-box runner could not run it (state=%s). NOT judged.\n' "$s" "$state"
        unusable=$((unusable + 1)) ;;
      *)
        printf '  REFUSE   %s — off-box state=%s; this suite would shut the T1H door for the whole machine\n' "$s" "$state"
        cure_block "$s" "$state"
        refused=$((refused + 1)) ;;
    esac
  done <<< "$added"

  # ── RATCHET (SHRINK) ARM — advisory, never blocking ────────────────────────────────────────────
  # An excluded suite this change MODIFIES gets re-measured. If it now passes, its line has lost its
  # reason to exist and saying so is what stops the list becoming a permanent exemption list. It is
  # ADVISORY on purpose: refusing a land because someone fixed a suite and did not also delete a
  # manifest line would punish exactly the behaviour this arm is trying to produce.
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    excluded_has "$s" || continue
    state="$(run_suite "$s")"
    if [ "$state" = "green" ]; then
      printf '  RATCHET  %s is green off-box now — delete its line from scripts/offbox-excluded.manifest (advisory)\n' "$s"
      stuck=$((stuck + 1))
    fi
  done <<< "$modified"

  if [ "$refused" -gt 0 ]; then
    printf '\noffbox-admission-lint: ⛔ %d suite(s) above are not off-box-clean and this change ADDS them.\n' "$refused"
    printf '  Why it is refused HERE and not by CI: the off-box workflow never gates a land, so this\n'
    printf '  would land, red the hourly producer, write no off-box stamp, and shut deploy-live.sh\n'
    printf '  T1H — the only tier that advances on a positive result — for EVERY session on this box.\n'
    return 1
  fi
  printf 'offbox-admission-lint: %d added suite(s) checked, %d skipped, %d abstained, %d stuck ratchet entry(ies) — admit\n' \
         "$checked" "$skipped" "$unusable" "$stuck"
  return 0
}

# ── --selftest: every case proves a RED path fires or a GREEN path does not, both directions ─────
if [ "${1:-}" = "--selftest" ]; then
  fails=0; ran=0
  chk() { ran=$((ran + 1)); [ "$2" = "$3" ] || { printf 'FAIL %s: want %s got %s\n' "$1" "$2" "$3" >&2; fails=1; }; }

  d="$(mktemp -d)" || exit 2
  mkdir -p "$d/scripts" "$d/tests"
  : > "$d/tests/green.bats"; : > "$d/tests/red.bats"; : > "$d/tests/cutty.bats"; : > "$d/tests/excl.bats"

  # A STUB PARTITION and a STUB RUNNER. Stubbing the runner is what makes the selftest hermetic and
  # fast; the REAL runner is exercised two-sidedly by tests/offbox-admission-lint.bats, which is
  # where the "does the probe reproduce a genuine off-box red" control lives. A selftest that shelled
  # out to the real bats corpus would be a 300s check nobody runs.
  cat > "$d/scripts/part.sh" <<'PART'
#!/bin/bash
case "${1:-}" in
  list)     printf 'tests/green.bats\ntests/red.bats\ntests/cutty.bats\n' ;;
  excluded) printf 'tests/excl.bats\n' ;;
esac
PART
  cat > "$d/scripts/run.sh" <<'RUN'
#!/bin/bash
# mimics `offbox-run.sh suites <s>`: header + one row, state keyed off the basename.
[ "${1:-}" = "suites" ] || exit 2
s="$2"
case "$s" in
  *green*|*excl*) st=green ;;
  *red*)          st=red ;;
  *cutty*)        st=cut ;;
  *)              st=missing ;;
esac
printf '# suite\tstate\tok\tnotok\trc\tsecs\n'
printf '%s\t%s\t1\t0\t0\t1\n' "$s" "$st"
RUN
  chmod +x "$d/scripts/part.sh" "$d/scripts/run.sh"
  export CC_OFFBOX_ADM_ROOT="$d" CC_OFFBOX_ADM_PARTITION="$d/scripts/part.sh" CC_OFFBOX_ADM_RUNNER="$d/scripts/run.sh"

  run_lint() { lint_range "" "$1" 0 1 >/dev/null 2>&1; printf '%s' "$?"; }

  # S1/S2 — the two directions of the admission arm. S2 is the control that proves S1 is not vacuous.
  chk "S1 an ADDED suite that is red off-box ⇒ REFUSE" 1 "$(run_lint 'tests/red.bats')"
  chk "S2 control — an ADDED suite that is green ⇒ admit" 0 "$(run_lint 'tests/green.bats')"

  # S3 — a CUT is a refusal HERE, and that is deliberate and worth stating. `deploy-live.sh`'s stamp
  # semantics read cut/hung as ELIGIBLE, and offbox-run's fold correctly emits `cut` rather than
  # `red` for one. But the workflow's conclusion is BINARY — green or nothing — so a suite that only
  # ever times out off-box produces no green, forever, and holds T1H shut exactly as hard as a
  # failing one. Admitting a suite that cannot finish inside the producer's own 300s bound would be
  # admitting a permanent non-verdict. It is refused at the source, where the author can split it.
  chk "S3 an ADDED suite that CUTS off-box ⇒ REFUSE (a permanent non-verdict shuts the door too)" 1 "$(run_lint 'tests/cutty.bats')"

  # S4 — out-of-partition is SKIPPED, never run. This is what makes cure (b) actually work: the
  # author pastes the manifest line, the suite leaves the partition, and the same gate now admits.
  chk "S4 an ADDED suite already EXCLUDED ⇒ skipped, land proceeds (the gate allows its own cure)" 0 "$(run_lint 'tests/excl.bats')"

  # S5 — a suite the runner cannot speak about must ABSTAIN, never convict (R6).
  chk "S5 a runner NON-VERDICT abstains, never refuses" 0 "$(run_lint 'tests/nosuch.bats')"

  # S6 — mixed: one green beside one red still refuses. A gate that folded a red into a pass because
  # something else passed would be the exact conflation this file was written to remove.
  chk "S6 green + red ⇒ still REFUSE" 1 "$(run_lint 'tests/green.bats,tests/red.bats')"

  # S7 — the empty set admits. A change that adds NO suite must never be blocked by this arm; that
  # is the fleet-wide hard stop §9 measures and every sibling arm's own-scope contract forbids.
  chk "S7 no added suites ⇒ admit (never a fleet-wide stop)" 0 "$(run_lint '')"

  # S8 — the refusal must actually CARRY the cure. A gate whose refusal does not hand over the
  # paste-ready line sends the author to a CI round-trip for the measurement, which is the loop this
  # file exists to remove; assert the manifest line and the repro command are both present.
  out8="$(lint_range "" 'tests/red.bats' 0 1 2>&1)"
  case "$out8" in *'offbox-run.sh suites tests/red.bats'*) : ;; *) printf 'FAIL S8a: refusal lacks the repro command\n' >&2; fails=1 ;; esac
  case "$out8" in *'off-box state=red (offbox-admission-lint, at land)'*) : ;; *) printf 'FAIL S8b: refusal lacks the measured manifest line\n' >&2; fails=1 ;; esac
  ran=$((ran + 2))

  # S9 — the shrink arm. An EXCLUDED suite that is green now must be reported as stuck, and must NOT
  # block. Both halves matter: reporting nothing lets the list rot; refusing would punish the fix.
  # (the shrink arm needs a real git range, so its two directions are pinned in
  # tests/offbox-admission-lint.bats rather than here — a stub range would assert nothing.)

  rm -rf "$d"
  if [ "$fails" -eq 0 ]; then
    echo "offbox-admission-lint --selftest: ${ran}/${ran} — REFUSES an added suite that is red or that CUTS, and CARRIES the repro command + the measured manifest line in the refusal; ADMITS a green one, an already-excluded one (its own cure), an empty added-set, and a runner non-verdict (R6 abstain); a red beside a green still refuses."
    exit 0
  fi
  echo "offbox-admission-lint --selftest: FAILED — the gate does not discriminate." >&2
  exit 1
fi

# ── entry ────────────────────────────────────────────────────────────────────────────────────────
RANGE=""; ADDED=""; ADDED_SUPPLIED=0; WORKING=0
while [ $# -gt 0 ]; do
  case "$1" in
    --range)   RANGE="${2:?--range needs a git range}"; shift 2 ;;
    --added)   ADDED="${2-}"; ADDED_SUPPLIED=1; shift 2 ;;   # SET-BUT-EMPTY is a real position
    --working) WORKING=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         die "unknown argument: $1 (try --help)" 2 ;;
  esac
done

if [ "$ADDED_SUPPLIED" = "0" ] && [ -z "$RANGE" ]; then
  # Infer, and SAY SO — an inferred scope a reader cannot see is how a gate's verdict gets
  # misattributed to a range nobody chose (bats-shellcheck-lint states the same rule).
  if ! ( cd "$(root_dir)" && git rev-parse --git-dir >/dev/null 2>&1 ); then
    die "no --range/--added given and $(root_dir) is not a git work tree — refusing to invent a change-set" 2
  fi
  base="$( cd "$(root_dir)" && git merge-base "origin/$TRUNK" HEAD 2>/dev/null )" \
    || die "no --range given and no resolvable origin/$TRUNK — refusing to invent a change-set" 2
  [ -n "$base" ] || die "no --range given and no resolvable origin/$TRUNK — refusing to invent a change-set" 2
  RANGE="$base..HEAD"
  printf 'offbox-admission-lint: no range given — inferred own-scope %s in %s\n' "$RANGE" "$(root_dir)"
fi

lint_range "$RANGE" "$ADDED" "$WORKING" "$ADDED_SUPPLIED"
