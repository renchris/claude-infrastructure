#!/usr/bin/env bats
# pane-spawn-memo.bats — the per-file memo inside pane-spawn-coverage-lint (backlog 91c6f91062ae).
#
# THE SPLIT WITH --selftest IS THE REPO'S STANDING RULE: `--selftest` owns the DETECTOR on synthetic
# fixtures with no history — including the three could-not-run cases this memo depends on — and this
# suite owns COVERAGE AGAINST A REAL COMMITTED CORPUS. Asking either to do the other's job yields a
# vacuous pass. It is also mechanical here: memo_init keys off the CURRENT directory's git state,
# not the scan root, so a --selftest left memo-armed would write entries for /tmp fixtures into
# whatever repo the caller happens to be standing in.
#
# WHY THIS MEMO EXISTS. The arm costs 19.5 ms/file over 404 files — 7.3s, measured through
# ship-land's own_run — and every optimistic round a sibling invalidates (exit 42) re-pays it over a
# tree identical except for the sibling's delta.
#
# WHAT IS PINNED IS THE MEMO AGREEING WITH AN UNMEMOIZED RUN, never that it is fast. A memo that
# returns a green it did not earn is strictly worse than the 7s it saves (repo memory:
# gate-default-decides-failure-direction).
#
# 🚨 CASE 1 IS A POSITIVE CONTROL AND IT COMES FIRST BY CONSTRUCTION. The memo refuses on a dirty
# worktree and stays fail-closed OFF if the fixture omits the library, so a suite that got either
# wrong would go silently memo-OFF and every case below would pass while asserting nothing. The
# sibling suite shipped exactly that — a fixture that copied the lint but not gate-memo.sh — and
# three of its cases had been asserting nothing until this control was put first.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"          # hermeticity: never the operator's live ~
  mkdir -p "$HOME"

  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/pane-spawn-coverage-lint.sh"

  # A REAL slice of the corpus in a repo of its own, so the memo's clean-tree precondition is ours
  # to control rather than the operator's.
  CORPUS="$BATS_TEST_TMPDIR/corpus"
  mkdir -p "$CORPUS/scripts/lib"
  # THE MEMO LIBRARY MUST TRAVEL WITH THE LINT. The lint sources "$SELF_ROOT/scripts/lib/
  # gate-memo.sh" where SELF_ROOT is derived from its own resolved path — so a fixture that copies
  # the lint but not the lib gets a lint whose memo is fail-closed OFF. That is correct behaviour
  # and a silent one; case 1 below is the only reason this suite is not still asserting nothing.
  cp "$REPO/scripts/lib/gate-memo.sh" "$CORPUS/scripts/lib/"
  # Glob into an array and slice, never `ls | head`: the gate's own .bats shellcheck ratchet blocks
  # on SC2012, one findings-bearing line per use.
  ALL=( "$REPO"/scripts/*.sh )
  for f in "${ALL[@]:0:30}"; do cp "$f" "$CORPUS/scripts/"; done
  cp "$LINT" "$CORPUS/scripts/"                 # the lint must be able to find itself under ROOT
  cd "$CORPUS" || exit 1
  git init -q .
  git add -A
  git -c user.email=tester@example.com -c user.name=tester commit -qm init
}

# run_lint — the lint against the fixture corpus, combined output. CC_PSC_OWN is exported the way
# ship-land's own_run does. Set-EMPTY is the "this land changed no scannable file" posture, so a
# pre-existing finding in the copied slice prints ADVISORY and the run stays rc 0 — which keeps
# every case below about the MEMO rather than about which script the slice happened to include.
run_lint() {
  ( cd "$CORPUS" || exit 2
    CC_PSC_OWN="${1-}" bash "$CORPUS/scripts/pane-spawn-coverage-lint.sh" "$CORPUS" 2>&1 )
}

# An ABSENT attestation answers -1, never the empty string: `[ "" -gt 1 ]` aborts the test with a
# usage error, which reads as a red for the wrong reason and hides which assertion actually failed.
carried() {
  local v; v="$(printf '%s\n' "$1" | sed -n 's/.*per-file memo — \([0-9]*\) verdict(s) carried.*/\1/p' | tail -1)"
  printf '%s' "${v:--1}"
}
proven() {
  local v; v="$(printf '%s\n' "$1" | sed -n 's/.*carried, \([0-9]*\) proven fresh.*/\1/p' | tail -1)"
  printf '%s' "${v:--1}"
}

@test "POSITIVE CONTROL: the memo arms and carries on an unchanged committed corpus" {
  first="$(run_lint)"
  [[ "$first" == *"per-file memo"* ]] || { echo "MEMO NEVER ARMED — every case below is vacuous"; echo "$first"; return 1; }
  [ "$(carried "$first")" -eq 0 ]              # nothing earned yet
  [ "$(proven "$first")" -gt 0 ]
  second="$(run_lint)"
  [ "$(carried "$second")" -gt 0 ]             # THE ASSERTION: it actually carried
  [ "$(proven "$second")" -lt "$(proven "$first")" ]
  # 🚨 NOT `proven == 0`, and the difference is a real property rather than a slack assertion. The
  # slice includes scripts that genuinely spawn panes, and with CC_PSC_OWN set-EMPTY each of those
  # prints an ADVISORY line — an EMISSION, which gate-memo invariant 1 forbids caching. So a
  # steady-state run re-proves exactly the emitting files, forever, by design. What is pinned
  # instead is that the floor is STABLE: a third run must carry and re-prove exactly what the
  # second did. A memo that kept slipping would show up here as a moving floor.
  third="$(run_lint)"
  [ "$(carried "$third")" -eq "$(carried "$second")" ]
  [ "$(proven "$third")" -eq "$(proven "$second")" ]
}

@test "a carried run reports the SAME verdicts as an unmemoized one" {
  run_lint >/dev/null                                    # warm
  warm="$(run_lint)"
  cold="$( cd "$CORPUS" || exit 2
           CC_PSC_MEMO=off CC_PSC_OWN="" bash "$CORPUS/scripts/pane-spawn-coverage-lint.sh" "$CORPUS" 2>&1 )"
  # Compare the VERDICT lines, not the attestation or the census (both differ by construction: the
  # census reports how many files this RUN scanned, which is the whole point of the memo).
  w="$(printf '%s\n' "$warm" | grep -v 'per-file memo' | grep -v 'pane-spawn site(s)' || true)"
  c="$(printf '%s\n' "$cold" | grep -v 'per-file memo' | grep -v 'pane-spawn site(s)' || true)"
  [ "$w" = "$c" ]
}

@test "editing one file re-proves THAT file and no other" {
  # THE TARGET IS A FILE WE KNOW IS CACHEABLE. Editing whichever real script sorts last would be a
  # coin flip: the slice contains genuine spawners, those emit an ADVISORY under set-EMPTY own-scope
  # and are never cached, so editing one would move neither counter and the case would pass while
  # proving nothing. A file with no primitive in it is carried by construction.
  printf '# a file with no terminal primitive in it at all\n:\n' > "$CORPUS/scripts/zz-clean.sh"
  ( cd "$CORPUS" && git add -A && git -c user.email=t@e.x -c user.name=t commit -qm clean )
  run_lint >/dev/null
  before="$(run_lint)"
  base="$(proven "$before")"                   # the emitting files, which re-prove every run
  n="$(carried "$before")"
  [ "$n" -gt 1 ]
  printf '\n# a comment that changes bytes and no verdict\n' >> "$CORPUS/scripts/zz-clean.sh"
  ( cd "$CORPUS" && git add -A && git -c user.email=t@e.x -c user.name=t commit -qm edit )
  after="$(run_lint)"
  [ "$(proven "$after")" -eq $((base + 1)) ]   # exactly the edited file, on top of the floor
  [ "$(carried "$after")" -eq $((n - 1)) ]
}

@test "a change to the LINT ITSELF invalidates every carried verdict" {
  run_lint >/dev/null
  before="$(run_lint)"
  [ "$(carried "$before")" -gt 1 ]
  printf '\n# read-set change: the lint blob is part of the key\n' >> "$CORPUS/scripts/pane-spawn-coverage-lint.sh"
  ( cd "$CORPUS" && git add -A && git -c user.email=t@e.x -c user.name=t commit -qm lint-edit )
  after="$(run_lint)"
  [ "$(carried "$after")" -eq 0 ]
  [ "$(proven "$after")" -gt 0 ]
}

@test "CC_PSC_WINDOW is in the read set — it decides tier 2 directly, with no byte of any file moving" {
  run_lint >/dev/null
  before="$(run_lint)"
  [ "$(carried "$before")" -gt 1 ]
  after="$( cd "$CORPUS" || exit 2
            CC_PSC_WINDOW=99 CC_PSC_OWN="" bash "$CORPUS/scripts/pane-spawn-coverage-lint.sh" "$CORPUS" 2>&1 )"
  [ "$(carried "$after")" -eq 0 ]
}

@test "the ALLOWLIST is in the read set — it selects the population and renames green" {
  run_lint >/dev/null
  before="$(run_lint)"
  [ "$(carried "$before")" -gt 1 ]
  after="$( cd "$CORPUS" || exit 2
            CC_PSC_ALLOWLIST="scripts/nothing-here.sh::because" CC_PSC_OWN="" \
            bash "$CORPUS/scripts/pane-spawn-coverage-lint.sh" "$CORPUS" 2>&1 )"
  [ "$(carried "$after")" -eq 0 ]
}

@test "a live finding is RE-REPORTED, never replayed from the cache" {
  printf 'kt launch --type=window --cwd=current\n' > "$CORPUS/scripts/zz-spawner.sh"
  ( cd "$CORPUS" && git add -A && git -c user.email=t@e.x -c user.name=t commit -qm spawner )
  first="$(run_lint "scripts/zz-spawner.sh" || true)"
  [[ "$first" == *"zz-spawner.sh"* ]] || { echo "$first"; return 1; }
  second="$(run_lint "scripts/zz-spawner.sh" || true)"
  # The finding must appear BOTH times — a cached red would print it once and go quiet.
  [[ "$second" == *"zz-spawner.sh"* ]]
}

@test "🚨 an ADVISORY finding is an EMISSION, so own-scope can stay out of the key" {
  # CC_PSC_OWN is deliberately absent from the read set, and the argument for that is that own-scope
  # decides only WHICH emission an uncovered site becomes — blocking, or ADVISORY — never whether
  # there is one. This case is what makes that argument checkable rather than asserted.
  #
  # THE ORDER IS THE DISCRIMINATOR. Warm the memo with the spawner OUTSIDE the own-set, where its
  # only output is an ADVISORY line. If the emit detector counted `flagged` alone, that run would
  # bank a green for a file with an uncovered site, and the later in-scope run — sharing the key,
  # because own-scope is not in it — would hit the cache and go SILENTLY GREEN over a real spawner.
  printf 'kt launch --type=window --cwd=current\n' > "$CORPUS/scripts/zz-spawner.sh"
  ( cd "$CORPUS" && git add -A && git -c user.email=t@e.x -c user.name=t commit -qm spawner )
  advisory="$(run_lint "scripts/somebody-else.sh" || true)"
  [[ "$advisory" == *"ADVISORY"*"zz-spawner.sh"* ]] || { echo "$advisory"; return 1; }
  blocking="$(run_lint "scripts/zz-spawner.sh" || true)"
  [[ "$blocking" == *"zz-spawner.sh"* ]] || { echo "$blocking"; return 1; }
  # …and it must be the BLOCKING form, not the advisory one replayed.
  [[ "$blocking" != *"ADVISORY"*"zz-spawner.sh"* ]]
}

@test "🚨 a run whose predicate could not RUN records NOTHING — the veto is ABSOLUTE, not a delta" {
  # THIS IS THE ONE DEFECT THE SIBLING LINT SHIPPED (test-hermeticity, one iteration, caught only by
  # its own selftest). A veto written as a per-file DELTA vetoes only the FIRST file whose predicate
  # dies: every file after it compares equal to its own baseline, comes out unchanged, and is
  # RECORDED — out of a run that exits 2 and whose whole point is that it produced no verdict. Every
  # unrunnable state here is fail-SAFE (a sentinel, never a fabricated finding), so a non-verdict
  # looks exactly like a clean file at the record site and nothing else could catch this.
  #
  # THE VICTIM IS THE FIRST FILE IN THE POPULATION, and that choice is what makes the case
  # discriminate. CHECK_FAILED vetoes from the failure ONWARD — files scanned before it had working
  # predicates and genuinely emitted nothing, so their verdicts are real and are correctly banked.
  # Break the LAST file and both answers leave N-1 files recorded, and the case says nothing. Break
  # the FIRST and they separate completely: absolute ⇒ 0 carried, delta ⇒ every other file carried.
  run_lint >/dev/null                                   # warm: everything earned
  before="$(run_lint)"
  n="$(carried "$before")"
  [ "$n" -gt 1 ]

  # The same find the lint's own collect_files runs, minus the two names it skips before scanning.
  victim=""
  while IFS= read -r c; do
    case "$(basename "$c")" in pane-spawn-coverage-lint.sh|pane-spawn-log.sh) continue ;; esac
    victim="$c"; break
  done < <(find "$CORPUS/scripts" -type f \( -name '*.sh' -o -name '*.py' -o ! -name '*.*' \))
  [ -n "$victim" ]

  # A path-matching shim, so ONLY the site scan dies: this lint also greps a herestring and greps
  # the allowlist with no path argument, and a blanket "make grep fail" would kill those too and red
  # the case for a reason it does not name.
  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  REAL_GREP="$(command -v grep)"
  { echo '#!/bin/bash'
    printf 'for a in "$@"; do [ "$a" = "%s" ] && exit 3; done\n' "$victim"
    printf 'exec %s "$@"\n' "$REAL_GREP"
  } > "$SHIM/grep"
  chmod +x "$SHIM/grep"

  out="$( cd "$CORPUS" || exit 2
          rm -rf "$(git rev-parse --git-common-dir)/ship-land-memo"
          PATH="$SHIM:$PATH" CC_PSC_RETRY_SLEEP=0 CC_PSC_OWN="" \
          bash "$CORPUS/scripts/pane-spawn-coverage-lint.sh" "$CORPUS" 2>&1 || true )"
  [[ "$out" == *"UNUSABLE"* ]] || { echo "$out"; return 1; }   # the run really did produce no verdict

  # THE ASSERTION: with the scan restored, EVERY file must be proven fresh again. A single carried
  # verdict here means the unusable run banked one, which is the delta bug.
  after="$(run_lint)"
  [ "$(carried "$after")" -eq 0 ]
  [ "$(proven "$after")" -gt 1 ]
}

@test "a dirty worktree disarms the memo entirely" {
  run_lint >/dev/null
  printf '\n# uncommitted\n' >> "$CORPUS/scripts/pane-spawn-coverage-lint.sh"
  out="$(run_lint)"
  [[ "$out" != *"per-file memo"* ]]
}

@test "CC_PSC_MEMO=off disarms it" {
  out="$( cd "$CORPUS" || exit 2
          CC_PSC_MEMO=off CC_PSC_OWN="" bash "$CORPUS/scripts/pane-spawn-coverage-lint.sh" "$CORPUS" 2>&1 )"
  [[ "$out" != *"per-file memo"* ]]
}

# run the lint with the memo off and an explicit own-set, returning its rc through $status.
run_lint_own() {
  ( cd "$CORPUS" || exit 2
    CC_PSC_MEMO=off CC_PSC_OWN="$1" bash "$CORPUS/scripts/pane-spawn-coverage-lint.sh" "$CORPUS" 2>&1 )
}

@test "🚨 own-scope still BLOCKS when the own-set is past the pipe-buffer regime" {
  # THE MECHANISM ARM for the own-scope membership test. Every case above hands the lint an own-set
  # of at most a few hundred bytes, so none of them can see the failure this pins: under
  # `set -uo pipefail` a `grep -q` membership test exits at the first match, the producer takes
  # SIGPIPE, pipefail returns non-zero, the leading `!` turns that into TRUE — and a file that IS in
  # this land's own-set takes the ADVISORY branch. The finding stops blocking and the land proceeds.
  # A fail-OPEN in a blocking land gate, silent in the direction that matters.
  #
  # 2,600 fillers put the set past the measured always-inverted floor of 87,122 bytes for this
  # two-stage shape, with the needle on line 1, so a re-introduced -q fails every run rather than
  # one in twenty. The size is asserted, never assumed.
  #
  # A PURPOSE-BUILT FIXTURE, not a file the copied slice happens to contain. Every finding the
  # slice produces is TIER 2 — its files ARE instrumented — and tier 2 `continue`s BEFORE the
  # own-scope branch, so a subject drawn from the slice cannot reach the predicate under test at
  # all (measured while writing this: 2 notices, 0 advisory). This file carries a primitive and no
  # logger call anywhere, which is the tier-1 shape the own-scope branch actually gates.
  local rel="scripts/zz-uninstrumented-spawner.sh"
  local own own_neg fillers
  printf '#!/bin/bash\n# a spawner with no logger call anywhere in the file — tier 1 by construction\nkitty @ launch --type=os-window\n' \
    > "$CORPUS/$rel"

  # The fixture must REACH the branch before the arm can say anything about it: under a set-EMPTY
  # own-set the finding has to print as ADVISORY at rc 0. If it does not, fail loudly rather than
  # passing on a subject that was never judged.
  run run_lint_own ""
  [ "$status" -eq 0 ] || { echo "set-empty own-set did not stay rc 0 (rc=$status)" >&2; return 1; }
  printf '%s\n' "$output" | grep -qE "^ADVISORY ${rel}:" || { echo "fixture never reached the tier-1 own-scope branch" >&2; return 1; }

  fillers="$(awk 'BEGIN{ for (i = 1; i <= 2600; i++) printf "scripts/filler-%06d-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.sh\n", i }')"
  own="$(printf '%s\n%s' "$rel" "$fillers")"
  own_neg="$fillers"
  [ "${#own}" -ge 87122 ] || { echo "own-set ${#own} B is under the inverting floor" >&2; return 1; }

  # POSITIVE: the file IS in the own-set, so its finding must BLOCK, not print as advisory.
  run run_lint_own "$own"
  [ "$status" -eq 1 ] || { echo "past-floor own-set: an OWN file's finding did not block (rc=$status)" >&2; return 1; }
  printf '%s\n' "$output" | grep -qE "^${rel}:[0-9]+: pane-spawn" || { echo "no BLOCKING line for $rel" >&2; return 1; }

  # NEGATIVE: the same past-floor set without the needle must stay advisory at rc 0, so this arm
  # cannot pass by blocking on any large own-set.
  run run_lint_own "$own_neg"
  [ "$status" -eq 0 ] || { echo "a file outside a past-floor own-set blocked (rc=$status)" >&2; return 1; }
  printf '%s\n' "$output" | grep -qE "^ADVISORY ${rel}:" || { echo "$rel was not advisory outside the own-set" >&2; return 1; }
  true
}
