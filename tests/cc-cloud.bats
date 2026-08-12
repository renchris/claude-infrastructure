#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats, not suppressed noise: every @test body IS its own subshell, so an
#   `export` inside one is *meant* to be test-local (SC2030/SC2031), and setup()'s helpers are
#   invoked from those test subshells rather than from file scope (SC2329).
#
# cc-cloud — the off-box session reconciler's state function
# (docs/plans/CLOUD_OBSERVABILITY.md §3, §4). One test per arm of the total function:
#   U0 UNKNOWN · C1 NOT-STARTED · C2 BOOTING · C3 LANDED · C4 STALLED · C5 ALIVE · C6 ABANDONED
# plus the disciplines that this design exists to hold: absence-vs-unreachable, ordering of C3
# before C4, the sidecar-history precondition on C4, the `is-offbox` primitive the three lying
# local instruments call, the frozen row schema, and read-only-ness against git.
#
# ── ABSORBED SUITE: tests/cc-cloud-watch.bats (backlog 163676679912) ──────────────────────────────
# `bin/cc-cloud-watch` was a second, independent implementation of the same observable set, landed
# in the same commit by a sibling session. It is deleted; its two verbs with no home here —
# `preflight` and `list` — moved into the subject and their tests moved into this file. Its verdict
# arms map onto the state function already covered above with nothing lost:
#   nofetch → U0 UNKNOWN ("could not look" never folds into a fault verdict — same discipline)
#   waiting → C2 BOOTING / C5 ALIVE      fresh → C5 after a poll advance
#   dark    → C1 NOT-STARTED / C4 STALLED / C6 ABANDONED      retired → the retire test
#
# ── FIXTURE ORDERING IS LOAD-BEARING: declare BEFORE push ─────────────────────────────────────────
# `declare` now probes the remote once and records the sha the branch held BEFORE the fire (migrated
# from cc-cloud-watch's `record`). So "push, then declare" no longer models a session that pushed —
# it models a branch that ALREADY EXISTED, which is C1/C2, not C5. Four fixtures below were
# reordered for that reason: the old ordering asserted ALIVE off a ref the declared session had
# never touched. That is not a test that became wrong; it is a test that was always describing the
# wrong situation, and the baseline is what made the difference visible.
#
# HERMETIC BY CONSTRUCTION: setup() fixtures $HOME, the declaration store and the clock, and every
# "remote" is a REAL local bare repository created in $BATS_TEST_TMPDIR. NO test touches the
# network, the operator's ~/.claude, or any real remote.
#
# REAL ARTIFACT, NOT A STUB: the correctness claim under test is what `git ls-remote` actually
# returns — rc=0+empty for a reachable remote missing the ref, versus rc=128+empty for an
# unreachable one. Stubbing git would test the stub and would have let exactly the conflation this
# file guards against ship. Every fixture is therefore driven through real `git init`/`push`.
#
# POSITIVE CONTROLS: every absence assertion ("no row", "zero rows", "never STALLED") is paired IN
# THE SAME TEST with a case that DOES fire off the same fixture. This is not ceremony — cc-cloud's
# own --selftest reported a green on a `declare` that had silently failed, where UNKNOWN was the
# right answer for the wrong reason. A detector that fires on nothing is not a detector.
#
# RED-PROOF: every test below fails against the pristine pre-change tree, where bin/cc-cloud does
# not exist:
#   t=$(mktemp -d); git archive HEAD | tar -x -C "$t"
#   CC_CLOUD_SUBJECT_ROOT="$t" bats tests/cc-cloud.bats     # all fail: "cc-cloud is missing"
#
# DEAD-ASSERTION DISCIPLINE: bats runs each body under `set -eET`, and bash exempts `[[ ]]`, `(( ))`
# and `! cmd` from errexit — so a non-final occurrence of those is a DEAD assertion that always
# passes (scripts/bats-assert-liveness.py). This suite uses POSIX `[ ]` and appends `|| false`
# wherever a non-final negation is used.
#
# NO WALL-CLOCK: every time-dependent arm is driven by CC_CLOUD_NOW, never by sleeping
# (scripts/test-walltime-lint.sh).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ROOT="${CC_CLOUD_SUBJECT_ROOT:-$REPO}"
  CLOUD="$ROOT/bin/cc-cloud"

  D="$BATS_TEST_TMPDIR"

  # Fixture $HOME: cc-cloud's declaration store defaults to ~/.claude/autonomy/cloud, so an
  # unfixtured HOME would write into the operator's live autonomy dir. The repo's hermeticity
  # ratchet (scripts/test-hermeticity-lint.sh) runs in the land gate and fail-fasts on that.
  export HOME="$D/home"; mkdir -p "$HOME"

  export CC_CLOUD_STATE="$D/state"
  export CC_CLOUD_NOW=2000000000
  export GIT_CONFIG_NOSYSTEM=1

  T0=2000000000

  have_subject() {   # RED-proof legibility: name the absence instead of dying on 127
    [ -x "$CLOUD" ] || { echo "cc-cloud is missing or not executable at $CLOUD"; return 1; }
  }
  cloud() { "$CLOUD" "$@"; }

  bare() { # $1=name → a real bare repo path, echoed
    git init -q --bare "$D/$1.git" >/dev/null 2>&1
    printf '%s' "$D/$1.git"
  }
  # Push a real commit onto a real bare remote, optionally writing a file first.
  push_ref() { # $1=bare-path $2=branch [$3=file $4=content]
    local w="$D/w$RANDOM"
    git init -q "$w" >/dev/null 2>&1
    # BUILD ON TOP of the branch when it already exists. Every call inits a FRESH repo, so without
    # this a second push to the same branch carries an unrelated root commit — a non-fast-forward
    # the remote rejects, which under errexit aborts the CALLER rather than this helper. That is
    # what made "C4 poll resets the stall clock when the ref actually advances" red: the one test
    # that pushes the same branch twice, i.e. the only one that models what a cloud worker does.
    # A real worker advances a ref; the fixture must too, or the advance it asserts is not an
    # advance at all.
    if git -C "$w" fetch -q "$1" "refs/heads/$2" >/dev/null 2>&1; then
      git -C "$w" reset -q --hard FETCH_HEAD >/dev/null 2>&1 || true
    fi
    if [ -n "${3:-}" ]; then
      mkdir -p "$(dirname "$w/$3")"; printf '%s' "${4:-x}" > "$w/$3"
      git -C "$w" add -A >/dev/null 2>&1
      git -C "$w" -c user.email=t@t -c user.name=t commit -q -m seed >/dev/null 2>&1
    else
      git -C "$w" -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed >/dev/null 2>&1
    fi
    git -C "$w" push -q "$1" "HEAD:refs/heads/$2" >/dev/null 2>&1
    git -C "$w" rev-parse HEAD
  }
  # A working clone whose `origin` is a real bare remote — what `preflight` inspects. Optionally
  # pushes $2 so the "branch is visible off-box" arm has both a present and an absent case.
  work_with_remote() { # $1=bare-path [$2=branch-to-push] → work path
    local w="$D/pf$RANDOM"
    git init -q "$w" >/dev/null 2>&1
    git -C "$w" remote add origin "$1" >/dev/null 2>&1
    git -C "$w" -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed >/dev/null 2>&1
    if [ -n "${2:-}" ]; then
      git -C "$w" push -q origin "HEAD:refs/heads/$2" >/dev/null 2>&1
    fi
    printf '%s' "$w"
  }
  # A local repo carrying a trunk ref, for the content-verified LANDED arm (O4).
  trunk_repo() { # $1=name $2=path-that-is-present-on-trunk → repo path
    local r="$D/$1"
    git init -q "$r" >/dev/null 2>&1
    mkdir -p "$(dirname "$r/$2")"; printf 'landed' > "$r/$2"
    git -C "$r" add -A >/dev/null 2>&1
    git -C "$r" -c user.email=t@t -c user.name=t commit -q -m landed >/dev/null 2>&1
    git -C "$r" update-ref refs/remotes/origin/main HEAD >/dev/null 2>&1
    printf '%s' "$r"
  }

  states() { "$CLOUD" --json | sed -n 's/.*"state":"\([^"]*\)".*/\1/p'; }
  rows()   { "$CLOUD" --json | grep -c '"kind":"cloud-session"' || true; }
  tstate() { "$CLOUD" --table | awk -v i="$1" '$1==i {print $2}'; }
  field()  { "$CLOUD" --json | sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" | head -1; }
}

# ── C2 / C1: absence inside vs past the boot budget ───────────────────────────────────────────────
@test "C2 BOOTING is silent inside the boot budget; C1 NOT-STARTED rows past it" {
  have_subject
  r="$(bare rem)"
  cloud declare --id early --branch feat/a --remote "$r" --repo "" --boot 900

  # Inside the budget: expected, not a fault.
  [ "$(rows)" -eq 0 ]
  [ "$(tstate early)" = "BOOTING" ]

  # POSITIVE CONTROL on the same fixture: move only the clock and the SAME declaration must fire.
  export CC_CLOUD_NOW=$((T0 + 901))
  [ "$(rows)" -eq 1 ]
  [ "$(states)" = "NOT-STARTED" ]
  [ "$(field subject)" = "early" ]
}

# ── U0: the discriminator the whole design rests on ───────────────────────────────────────────────
@test "U0 an UNREACHABLE remote is UNKNOWN, never NOT-STARTED — absence != inability to look" {
  have_subject
  # Both remotes return EMPTY stdout from ls-remote. Only the exit code separates them: rc=0 for a
  # reachable remote missing the ref, rc=128 for a remote that cannot be reached at all. Reading
  # emptiness alone would convict a live cloud session on a wifi blip.
  reachable="$(bare good)"
  cloud declare --id down --branch feat/a --remote "$D/no-such-remote.git" --repo "" --boot 900
  cloud declare --id up   --branch feat/a --remote "$reachable"            --repo "" --boot 900

  export CC_CLOUD_NOW=$((T0 + 5000))   # both are far past the boot budget

  [ "$(tstate down)" = "UNKNOWN" ]
  # A sensor that could not run emits NO row — "no sensor, no verdict".
  [ "$("$CLOUD" --json | grep -c '"subject":"down"' || true)" -eq 0 ]

  # POSITIVE CONTROL: the reachable one, identically aged, DOES convict.
  [ "$(tstate up)" = "NOT-STARTED" ]
  [ "$("$CLOUD" --json | grep -c '"subject":"up"' || true)" -eq 1 ]
}

@test "U0 --check FAILS on UNKNOWN — a check that could not run must never pass vacuously" {
  have_subject
  r="$(bare rem)"
  cloud declare --id ok --branch feat/a --remote "$r" --repo "" --boot 900
  run "$CLOUD" --check
  [ "$status" -eq 0 ]                       # control: a healthy board passes

  cloud declare --id down --branch feat/a --remote "$D/gone.git" --repo "" --boot 900
  run "$CLOUD" --check
  [ "$status" -ne 0 ]
}

# ── C5 ALIVE ─────────────────────────────────────────────────────────────────────────────────────
@test "C5 a pushed ref inside its budgets is ALIVE and silent" {
  have_subject
  r="$(bare rem)"
  # Declare FIRST, then push: that is what a session doing the work looks like. Pushing first would
  # seed the fire-time baseline with this very sha, making it a pre-existing branch (C1/C2).
  cloud declare --id live --branch feat/a --remote "$r" --repo "" --boot 900 --life 21600
  push_ref "$r" feat/a >/dev/null
  [ "$(tstate live)" = "ALIVE" ]
  [ "$(rows)" -eq 0 ]

  # CONTROL: the same declaration with no ref pushed is NOT silent once past boot.
  cloud declare --id nolive --branch feat/zzz --remote "$r" --repo "" --boot 900
  export CC_CLOUD_NOW=$((T0 + 5000))
  [ "$(tstate nolive)" = "NOT-STARTED" ]
}

# ── C4 STALLED, and its history precondition ─────────────────────────────────────────────────────
@test "C4 STALLED needs sidecar history — with none, it is never claimed" {
  have_subject
  r="$(bare rem)"
  cloud declare --id frozen --branch feat/a --remote "$r" --repo "" --stall 3600 --life 999999
  push_ref "$r" feat/a >/dev/null

  # No poll has ever run ⇒ no evidence the sha ever differed ⇒ no verdict is invented.
  export CC_CLOUD_NOW=$((T0 + 100000))
  [ "$(tstate frozen)" = "ALIVE" ]
  [ "$(rows)" -eq 0 ]

  # POSITIVE CONTROL: give it history at T0, and the identical situation now fires.
  export CC_CLOUD_NOW=$T0
  cloud poll >/dev/null
  export CC_CLOUD_NOW=$((T0 + 100000))
  [ "$(tstate frozen)" = "STALLED" ]
  [ "$(states)" = "STALLED" ]
}

@test "C4 poll resets the stall clock when the ref actually advances" {
  have_subject
  r="$(bare rem)"; push_ref "$r" feat/a >/dev/null
  cloud declare --id moving --branch feat/a --remote "$r" --repo "" --stall 3600 --life 999999
  cloud poll >/dev/null

  # Advance the remote, then poll again at a later clock: the sha changed, so `since` moves forward.
  push_ref "$r" feat/a file.txt second >/dev/null
  export CC_CLOUD_NOW=$((T0 + 3000))
  cloud poll >/dev/null

  export CC_CLOUD_NOW=$((T0 + 5000))   # 5000s since declare, but only 2000s at the current sha
  [ "$(tstate moving)" = "ALIVE" ]
  [ "$(rows)" -eq 0 ]

  # CONTROL: push the clock past the stall budget measured from the NEW sighting and it fires.
  export CC_CLOUD_NOW=$((T0 + 3000 + 3601))
  [ "$(tstate moving)" = "STALLED" ]
}

# ── C3 LANDED, and why it must precede C4 ────────────────────────────────────────────────────────
@test "C3 LANDED is content-verified on trunk, and OUTRANKS STALLED" {
  have_subject
  r="$(bare rem)"
  repo="$(trunk_repo work docs/thing.md)"
  # Both declared BEFORE the push, so both refs genuinely MOVED off their fire-time baseline and the
  # only thing separating them below is the O4 content check.
  cloud declare --id 'done' --branch feat/a --remote "$r" --repo "$repo" \
        --trunk origin/main --paths docs/thing.md --stall 3600 --life 999999
  cloud declare --id notdone --branch feat/a --remote "$r" --repo "$repo" \
        --trunk origin/main --paths docs/absent.md --stall 3600 --life 999999
  push_ref "$r" feat/a >/dev/null
  cloud poll >/dev/null

  # A finished session stops pushing ON PURPOSE. Ordering STALLED first would alarm forever on
  # every successful cloud session — an alarm that always fires carries no information.
  export CC_CLOUD_NOW=$((T0 + 100000))
  [ "$(tstate 'done')" = "LANDED" ]

  # POSITIVE CONTROL: an identically-aged, identically-frozen session whose declared path is NOT on
  # trunk falls through to STALLED — so the silence above is the LANDED arm, not a dead code path.
  [ "$(tstate notdone)" = "STALLED" ]
  [ "$(rows)" -eq 1 ]
}

# ── C6 ABANDONED ─────────────────────────────────────────────────────────────────────────────────
@test "C6 ABANDONED: pushed, never landed, past its lifetime" {
  have_subject
  r="$(bare rem)"
  cloud declare --id old --branch feat/a --remote "$r" --repo "" --life 3600 --stall 999999
  push_ref "$r" feat/a >/dev/null
  [ "$(tstate old)" = "ALIVE" ]           # control: inside the budget it is silent

  export CC_CLOUD_NOW=$((T0 + 3601))
  [ "$(tstate old)" = "ABANDONED" ]
  [ "$(states)" = "ABANDONED" ]
}

# ── the primitive the three lying instruments need ───────────────────────────────────────────────
@test "is-offbox is the abstain lookup: declared=0, retired=1, unknown=1, missing-arg=2" {
  have_subject
  r="$(bare rem)"
  cloud declare --id known --branch feat/a --remote "$r" --repo ""

  run "$CLOUD" is-offbox known
  [ "$status" -eq 0 ]
  run "$CLOUD" is-offbox never-declared
  [ "$status" -eq 1 ]
  run "$CLOUD" is-offbox
  [ "$status" -eq 2 ]

  cloud retire --id known >/dev/null
  run "$CLOUD" is-offbox known
  [ "$status" -eq 1 ]
}

@test "retire removes a session from reconciliation entirely" {
  have_subject
  r="$(bare rem)"
  cloud declare --id temp --branch feat/a --remote "$r" --repo "" --boot 900
  export CC_CLOUD_NOW=$((T0 + 5000))
  [ "$(rows)" -eq 1 ]                     # control: it was firing before the retire

  cloud retire --id temp >/dev/null
  [ "$(rows)" -eq 0 ]
  run "$CLOUD" --table
  [ "$status" -eq 0 ]
}

# ── the frozen row schema (bin/cc-blockers consumes this shape unchanged) ─────────────────────────
@test "rows carry the frozen 6-field schema, ASCII detail bounded at 44 bytes" {
  have_subject
  r="$(bare rem)"
  cloud declare --id schema-check --branch feat/a --remote "$r" --repo "" --boot 900
  export CC_CLOUD_NOW=$((T0 + 5000))

  line="$("$CLOUD" --json)"
  [ -n "$line" ]
  printf '%s' "$line" | grep -q '"kind":"cloud-session"'
  printf '%s' "$line" | grep -q '"recover_cmd":'
  printf '%s' "$line" | grep -q '"ts":[0-9]'
  # Parses as JSON, and `detail` obeys the byte bound the board's renderer pads against.
  detail="$(printf '%s' "$line" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["detail"])')"
  [ "$(printf '%s' "$detail" | wc -c | tr -d ' ')" -le 44 ]
  printf '%s' "$detail" | LC_ALL=C grep -q '^[ -~]*$'

  # The recover_cmd is the web UI, because that is the ONLY escalation surface a cloud session has:
  # neither claude binary on this box exposes a cloud-session query verb.
  printf '%s' "$line" | grep -q '"recover_cmd":"open '
}

# ── kill switch ──────────────────────────────────────────────────────────────────────────────────
@test "CC_CLOUD_RECONCILE=off emits zero rows, exit 0, and SAYS SO on stderr" {
  have_subject
  r="$(bare rem)"
  cloud declare --id offsw --branch feat/a --remote "$r" --repo "" --boot 900
  export CC_CLOUD_NOW=$((T0 + 5000))
  [ "$(rows)" -eq 1 ]                     # control: it fires while the switch is on

  export CC_CLOUD_RECONCILE=off
  # STDOUT ONLY. bats' `run` merges stderr into $output, and the disabled-reconciler warning is
  # deliberately written to stderr (the very next assertion proves it is there) — so an unredirected
  # `run` made this "zero rows on stdout" check fail on the presence of the warning it is paired
  # with. The two assertions must read different streams or they contradict each other.
  run bash -c "'$CLOUD' --json 2>/dev/null"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # A disabled reconciler must not look like a clean board.
  run bash -c "'$CLOUD' --json 2>&1 >/dev/null"
  printf '%s' "$output" | grep -q 'RECONCILE=off'
}

# ── declare is the gate: an undeclared cloud session is unobservable, so refuse to skip it ───────
@test "declare REFUSES without --id or --branch, and accepts an ordinary declaration" {
  have_subject
  r="$(bare rem)"
  run "$CLOUD" declare --branch feat/a --remote "$r"
  [ "$status" -eq 2 ]
  run "$CLOUD" declare --id x --remote "$r"
  [ "$status" -eq 2 ]
  run "$CLOUD" declare --id 'bad/id' --branch feat/a --remote "$r"
  [ "$status" -eq 2 ]

  # REGRESSION CONTROL: the newline guard is written as a literal because `$(printf '\n')` collapses
  # to "" and makes `*""*` match EVERY input — a guard that rejects everything looks exactly like a
  # guard that works, and it shipped once. This asserts the ordinary path still SUCCEEDS.
  run "$CLOUD" declare --id fine --branch feat/a --remote "$r" --repo ""
  [ "$status" -eq 0 ]
  [ -f "$CC_CLOUD_STATE/fine.decl" ]
}

# ── read-only ────────────────────────────────────────────────────────────────────────────────────
@test "reconciling writes no ref and fetches nothing into the local repo" {
  have_subject
  r="$(bare rem)"; push_ref "$r" feat/a >/dev/null
  repo="$(trunk_repo work docs/thing.md)"
  cloud declare --id ro --branch feat/a --remote "$r" --repo "$repo" --trunk origin/main --paths docs/thing.md

  before="$(git -C "$repo" for-each-ref --format='%(refname) %(objectname)' | sort)"
  "$CLOUD" --json >/dev/null
  "$CLOUD" --table >/dev/null
  after="$(git -C "$repo" for-each-ref --format='%(refname) %(objectname)' | sort)"
  [ "$before" = "$after" ]

  # CONTROL: the ref set is non-empty, so the comparison above is not two empty strings.
  [ -n "$before" ]
}

@test "an empty board is legible, not silent" {
  have_subject
  run "$CLOUD" --table
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'no cloud sessions declared'
  [ "$(rows)" -eq 0 ]
}

# ════════════════════════════════════════════════════════════════════════════════════════════════
# MIGRATED FROM tests/cc-cloud-watch.bats (backlog 163676679912) — the two verbs and the one
# behaviour that the deleted twin carried and this subject did not.
# ════════════════════════════════════════════════════════════════════════════════════════════════

# ── BASELINE: cc-cloud-watch's `record` seeded lastSha from the live remote; `declare` now does ───
@test "BASELINE a ref that ALREADY existed at fire time is not progress — C2 then C1, not C5" {
  have_subject
  r="$(bare rem)"
  push_ref "$r" feat/a >/dev/null            # the branch name is re-used: it exists BEFORE the fire
  cloud declare --id reused --branch feat/a --remote "$r" --repo "" --boot 900 --life 999999

  # Without the fire-time baseline this reads ALIVE — and stays silent for the whole life budget,
  # hiding the likeliest real failure (a session that never boots onto a re-used branch name).
  [ "$(tstate reused)" = "BOOTING" ]
  [ "$(rows)" -eq 0 ]

  # POSITIVE CONTROL, same remote and same clock: a session declared BEFORE its push has moved off
  # its baseline and stays ALIVE. So the verdicts here are the baseline arm, not the clock.
  cloud declare --id moved --branch feat/b --remote "$r" --repo "" --boot 900 --life 999999
  push_ref "$r" feat/b >/dev/null
  export CC_CLOUD_NOW=$((T0 + 5000))
  [ "$(tstate reused)" = "NOT-STARTED" ]
  [ "$(tstate moved)" = "ALIVE" ]
  [ "$(rows)" -eq 1 ]
  [ "$(field subject)" = "reused" ]
}

@test "BASELINE abstains when the fire-time probe could not run — unmeasured is not empty" {
  have_subject
  # Declare against a remote that does not exist yet, so declare's probe FAILS and no baseline is
  # recorded. Then bring the remote up and push. The ref is new, and the classifier must say so
  # rather than reading an unmeasured baseline as an empty one and convicting a live session.
  r="$D/late.git"
  cloud declare --id late --branch feat/a --remote "$r" --repo "" --boot 900 --life 999999
  [ -f "$CC_CLOUD_STATE/late.decl" ]
  run grep -c '^base_probe=' "$CC_CLOUD_STATE/late.decl"
  [ "$output" = "0" ]

  git init -q --bare "$r"
  push_ref "$r" feat/a >/dev/null
  export CC_CLOUD_NOW=$((T0 + 5000))
  [ "$(tstate late)" = "ALIVE" ]
  [ "$(rows)" -eq 0 ]

  # POSITIVE CONTROL: an identically-aged declaration WITH a measured baseline over the same,
  # now-reachable remote and the same branch DOES convict. The abstention above is the missing
  # measurement, not a classifier that has stopped firing.
  cloud declare --id measured --branch feat/a --remote "$r" --repo "" --boot 900 --life 999999
  grep -q '^base_probe=ok$' "$CC_CLOUD_STATE/measured.decl"
  export CC_CLOUD_NOW=$((T0 + 10000))
  [ "$(tstate measured)" = "NOT-STARTED" ]
}

# ── preflight: "design the observable set BEFORE firing", executable ─────────────────────────────
@test "preflight REFUSES a branch that exists only locally, and names the push that fixes it" {
  have_subject
  r="$(bare rem)"
  w="$(work_with_remote "$r" main)"
  git -C "$w" branch local-only

  run "$CLOUD" preflight --repo "$w" --branch local-only
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'is NOT on origin'
  # A refusal that does not say how to clear it is a wall, not a gate.
  printf '%s' "$output" | grep -q 'git push -u origin local-only'

  # POSITIVE CONTROL on the same repo and remote: the branch that IS pushed passes. Without this,
  # a preflight that refused everything would look exactly like one that works.
  run "$CLOUD" preflight --repo "$w" --branch main
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'PREFLIGHT PASS'
}

@test "preflight REFUSES a repo with no remote, and a path that is no repo at all" {
  have_subject
  norem="$D/norem"; git init -q "$norem"
  run "$CLOUD" preflight --repo "$norem" --branch main
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'no git remote'

  mkdir -p "$D/plain"
  run "$CLOUD" preflight --repo "$D/plain" --branch main
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'not a git repo'
}

@test "preflight warns but PASSES without --branch — an unchecked O2 is not a refusal" {
  have_subject
  r="$(bare rem)"
  w="$(work_with_remote "$r" main)"
  run "$CLOUD" preflight --repo "$w"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'no --branch given'
  printf '%s' "$output" | grep -q 'PREFLIGHT PASS (with warnings'
}

# ── list: the inventory, from disk, with no probe ────────────────────────────────────────────────
@test "list reads DISK ONLY — it still answers with the remote destroyed, where --table cannot" {
  have_subject
  r="$(bare rem)"
  cloud declare --id offline --branch feat/a --remote "$r" --repo "" --item deadbeef
  push_ref "$r" feat/a >/dev/null
  cloud poll >/dev/null

  rm -rf "$r"                                # the remote is now gone: any probe MUST fail

  run "$CLOUD" list --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"id":"offline"'
  printf '%s' "$output" | grep -q '"item":"deadbeef"'
  printf '%s' "$output" | python3 -c 'import json,sys; json.loads(sys.stdin.read())'

  # POSITIVE CONTROL: the probing renderer, on the identical fixture, cannot answer at all. That is
  # what makes the success above evidence of "no probe" rather than evidence of a reachable remote.
  [ "$(tstate offline)" = "UNKNOWN" ]
}

@test "list keeps RETIRED declarations for forensics; reconciliation drops them" {
  have_subject
  r="$(bare rem)"
  cloud declare --id keepme --branch feat/a --remote "$r" --repo ""
  cloud retire --id keepme >/dev/null

  run "$CLOUD" list --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"retired":true'

  # CONTROL: the reconciler's own enumeration DOES drop it — the two views differ on purpose.
  run "$CLOUD" --table
  printf '%s' "$output" | grep -q 'no cloud sessions declared'
}

# ── the TRUNK REFUSAL (backlog 55065a61b31c) ──────────────────────────────────────────────────────
# A session declared against the remote's DEFAULT branch cannot be told apart from its siblings:
# every other session's push to that branch reads as this session's heartbeat, and the observer
# reports a false state=ALIVE. Measured 2026-08-08. These cases pin the refusal, the thing it must
# NOT refuse, and the abstain path — because a guard that refused everything, or one that could
# never fire, would each pass a suite that only asserted the happy direction.

@test "D1 declare REFUSES the remote's default branch — trunk cannot be a per-session heartbeat" {
  have_subject
  local r; r="$(bare trunkref)"
  push_ref "$r" main                                  # HEAD of a bare repo follows its first branch
  run cloud declare --id trunkdecl --branch main --remote "$r" --repo ""
  [ "$status" -eq 2 ]
  [ ! -f "$CC_CLOUD_STATE/trunkdecl.decl" ] || { echo "REFUSED but still wrote a declaration"; false; }
  echo "$output" | grep -q "default branch of remote" || { echo "refusal did not name the cause: $output"; false; }
}

@test "D2 CONTROL: a per-session branch on the SAME remote still declares fine" {
  # The guard must not be a blanket refusal. Same remote, same call shape, one word different.
  have_subject
  local r; r="$(bare trunkref2)"
  push_ref "$r" main
  run cloud declare --id sessdecl --branch claude/sess-1 --remote "$r" --repo ""
  [ "$status" -eq 0 ]
  [ -f "$CC_CLOUD_STATE/sessdecl.decl" ] || { echo "a legitimate declaration was lost"; false; }
}

@test "D3 the predicate is ASKED, not a name list — a repo whose default is NOT 'main' is refused too" {
  # Refusing the spellings main/master/trunk would miss this repo and would still be a denylist
  # (memory: denylist-enumerates-spellings-not-the-class). The guard resolves the remote's OWN
  # default, so a repo defaulting to `release` is caught by the same code with no new spelling.
  have_subject
  local r; r="$(bare oddhead)"
  push_ref "$r" release
  run cloud declare --id odddecl --branch release --remote "$r" --repo ""
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "default branch of remote" || { echo "did not refuse a non-'main' default: $output"; false; }
}

@test "D4 ABSTAIN: an unreachable remote still declares — unobservable beats unverified" {
  # Both resolvers are blind here. The declaration must still be written: an UNDECLARED cloud
  # session is invisible to every oracle, which is strictly worse than one declared against a
  # branch we could not check. This is the same trade-off the baseline probe already makes, and it
  # is the case that proves the guard fails OPEN rather than turning a dead remote into a refusal.
  have_subject
  run cloud declare --id absdecl --branch main --remote "$D/nonexistent.git" --repo ""
  [ "$status" -eq 0 ]
  [ -f "$CC_CLOUD_STATE/absdecl.decl" ] || { echo "an unreachable remote turned into a refusal"; false; }
}
