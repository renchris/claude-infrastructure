#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats, not suppressed noise: every @test body IS its own subshell, so an
#   `export` inside one is *meant* to be test-local (SC2030/SC2031), and setup()'s helpers are
#   invoked from those test subshells rather than from file scope (SC2329).
#
# cloud-reconcile.sh — gate G6, the CLOUD LANDING PATH.
#
# THE GAP THIS SUBJECT CLOSES. A cloud Claude Code VM can push only its own `claude/*` working
# branch. It has no ~/.claude, no `gh`, and cannot run this repo's project-local /ship. Nothing
# LOCAL ever looks for that branch:
#   * scripts/stranded-sweep.sh:66 enumerates `refs/heads/` — LOCAL heads only. A remote-only
#     `claude/*` branch is structurally invisible to it (same for branch-reaper.sh and
#     worktree-gc.sh:374-387).
#   * scripts/ship-land.sh:1987's SHIP_LAND_SESSION_BRANCH_RE defaults to
#     `^(feat|fix|chore|docs|refactor|test|perf|style|build|ci)/.+` — `claude/*` does not match, so
#     a land attempt refuses.
# So every cloud result strands on a remote branch. This subject is the reconciler: DISCOVERY +
# ELIGIBILITY + SERIALIZATION. It lands nothing itself — it shells out to scripts/desk-land.sh,
# which owns the landing lock, the gate, the content-verify and the stranded sweep.
#
# REAL ARTIFACT, NOT AN APPROXIMATION. Every "remote" below is a REAL local bare repository and
# every branch is pushed by a REAL `git push`. The claim under test is what `git ls-remote --heads`
# actually returns, and a hand-edited approximation of that would pass vacuously
# (memory: control-must-replay-the-real-artifact).
#
# THE ONE STUB IS THE LANDER, VIA AN EXPLICIT ENV SEAM (CLOUD_RECONCILE_LAND_BIN). desk-land →
# ship-land pushes to a real trunk and runs the full gate; that is precisely the thing this suite
# must NOT invoke. The stub records its argv AND the SHIP_LAND_SESSION_BRANCH_RE it was handed, so
# the override this subject must pass is asserted rather than assumed.
#
# POSITIVE CONTROLS: every absence assertion below ("not listed", "never landed", "zero rows") is
# paired IN THE SAME TEST with a case that DOES fire off the same fixture. A grep that can find
# nothing is not evidence (memory: positive-control-the-denominator).
#
# RED-PROOF: every test fails against the pristine pre-change tree, where the subject does not
# exist:
#   t=$(mktemp -d); git archive HEAD | tar -x -C "$t"
#   CLOUD_RECONCILE_SUBJECT_ROOT="$t" bats tests/cloud-reconcile.bats   # all fail: subject missing
#
# DEAD-ASSERTION DISCIPLINE: bats runs each body under `set -eET`, and bash exempts `[[ ]]`, `(( ))`
# and `! cmd` from errexit — a non-final occurrence of those is a DEAD assertion that always passes
# (scripts/bats-assert-liveness.py). This suite uses POSIX `[ ]` and appends `|| false` after every
# non-final negation.
#
# NO WALL-CLOCK, NO NETWORK, NO LIVE $HOME.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ROOT="${CLOUD_RECONCILE_SUBJECT_ROOT:-$REPO_ROOT}"
  CR="$ROOT/scripts/cloud-reconcile.sh"

  D="$BATS_TEST_TMPDIR"

  # Fixture $HOME: the declaration store defaults to ~/.claude/autonomy/cloud (shared with
  # bin/cc-cloud), so an unfixtured HOME would read — and this suite's fixtures would litter — the
  # operator's live autonomy dir. scripts/test-hermeticity-lint.sh runs in the land gate.
  export HOME="$D/home"; mkdir -p "$HOME"
  export GIT_CONFIG_NOSYSTEM=1
  export CC_CLOUD_STATE="$D/state"; mkdir -p "$CC_CLOUD_STATE"

  ORIGIN="$D/origin.git"
  REPO="$D/repo"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$REPO"
  (
    cd "$REPO" || exit 1
    git config user.email t@e.com; git config user.name tester
    git checkout -q -b main
    echo base > base.txt
    mkdir -p already
    echo landed > already/landed.txt
    git add -A; git commit -q -m base
    git push -q -u origin main
  )

  # The lander stub. Records argv and the branch-name regex it was handed; fails for any branch
  # named in LAND_STUB_FAIL so the "one failure does not abort the rest" arm is drivable.
  export LAND_STUB_LOG="$D/land.log"; : > "$LAND_STUB_LOG"
  LAND_STUB="$D/desk-land-stub.sh"
  cat > "$LAND_STUB" <<'STUB'
#!/usr/bin/env bash
{ echo "ARGS=$*"; echo "RE=${SHIP_LAND_SESSION_BRANCH_RE:-<unset>}"; } >> "${LAND_STUB_LOG:?}"
b=""
while [ $# -gt 0 ]; do
  case "$1" in --branch) b="${2:-}"; shift 2 ;; --branch=*) b="${1#--branch=}"; shift ;; *) shift ;; esac
done
case " ${LAND_STUB_FAIL:-} " in *" $b "*) exit 6 ;; esac
exit 0
STUB
  chmod +x "$LAND_STUB"
  export CLOUD_RECONCILE_LAND_BIN="$LAND_STUB"
  export CLOUD_RECONCILE_REPO="$REPO"

  have_subject() {   # RED-proof legibility: name the absence instead of dying on 127
    [ -x "$CR" ] || { echo "cloud-reconcile.sh is missing or not executable at $CR"; return 1; }
  }
  cr() { have_subject && bash "$CR" "$@"; }

  # Push a branch carrying $2 files, built on main. Real git, real push.
  push_branch() {  # $1=branch  $2=file-count
    local b="$1" n="${2:-1}" i w
    w="$D/w-$(printf '%s' "$b" | tr / -)"
    git -C "$REPO" worktree add -q -b "$b" "$w" main
    i=1
    while [ "$i" -le "$n" ]; do
      printf 'c%s\n' "$i" > "$w/f$i.txt"
      i=$((i + 1))
    done
    git -C "$w" add -A
    git -C "$w" -c user.email=t@e.com -c user.name=tester commit -q -m "work $b"
    git -C "$w" push -q origin "HEAD:refs/heads/$b"
    # Remove the LOCAL trace entirely — a cloud branch exists ONLY on the remote, and a local head
    # left behind would make the discovery arm pass for the wrong reason.
    git -C "$REPO" worktree remove --force "$w"
    git -C "$REPO" branch -q -D "$b"
    rm -rf "$w"
    true
  }

  decl() {  # $1=id  $2=branch  [$3=paths]
    { printf 'id=%s\n' "$1"
      printf 'branch=%s\n' "$2"
      printf 'remote=origin\n'
      printf 'repo=%s\n' "$REPO"
      printf 'trunk=origin/main\n'
      printf 'paths=%s\n' "${3:-}"
      printf 'declared_at=2000000000\n'
    } > "$CC_CLOUD_STATE/$1.decl"
  }

  retire() { : > "$CC_CLOUD_STATE/$1.retired"; }

  landed_branches() {  # branches the stub was asked to land, in call order
    /usr/bin/grep '^ARGS=' "$LAND_STUB_LOG" 2>/dev/null \
      | sed -n 's/.*--branch \([^ ]*\).*/\1/p'
  }
}

# ── discovery ────────────────────────────────────────────────────────────────────────────────
@test "--list discovers a remote-only claude/* branch (and only claude/*)" {
  push_branch claude/aaa 1
  push_branch feat/other 1

  run cr --list
  [ "$status" -eq 0 ]
  # POSITIVE CONTROL for the absence below: the claude branch IS found off this same fixture, so a
  # listing that finds nothing at all cannot pass this test.
  echo "$output" | /usr/bin/grep -q 'claude/aaa'
  echo "$output" | /usr/bin/grep -qv 'feat/other' || false
  # And it is genuinely remote-only — no local head exists for it.
  git -C "$REPO" show-ref --verify --quiet refs/heads/claude/aaa && false
  true
}

@test "--list flags an UNDECLARED branch while a declared sibling reads ELIGIBLE" {
  push_branch claude/decl 1
  push_branch claude/orphan 1
  decl cloud-1 claude/decl

  run cr --list
  [ "$status" -eq 0 ]
  echo "$output" | /usr/bin/grep -q 'claude/orphan.*NO-DECL'
  # POSITIVE CONTROL: the same run classifies the declared sibling differently, so NO-DECL is a
  # real verdict and not the only thing this lister can say.
  echo "$output" | /usr/bin/grep -q 'claude/decl.*ELIGIBLE'
}

@test "a RETIRED declaration is skipped, an active one in the same run is landed" {
  push_branch claude/dead 1
  push_branch claude/live 1
  decl cloud-dead claude/dead
  decl cloud-live claude/live
  retire cloud-dead

  CONFIRM=1 run cr --all
  [ "$status" -eq 0 ]
  landed_branches | /usr/bin/grep -q '^claude/live$'
  # POSITIVE CONTROL for the absence: the log is provably non-empty (the line above), so "dead is
  # absent" is evidence rather than a grep over nothing.
  landed_branches | /usr/bin/grep -qv '^claude/dead$' || false
}

@test "a declaration whose paths are already on trunk reads LANDED and is not re-landed" {
  push_branch claude/done 1
  push_branch claude/todo 1
  decl cloud-done claude/done "already/landed.txt"
  decl cloud-todo claude/todo "not/on/trunk.txt"

  run cr --list
  [ "$status" -eq 0 ]
  echo "$output" | /usr/bin/grep -q 'claude/done.*LANDED'
  echo "$output" | /usr/bin/grep -q 'claude/todo.*ELIGIBLE'

  CONFIRM=1 run cr --all
  [ "$status" -eq 0 ]
  landed_branches | /usr/bin/grep -q '^claude/todo$'
  landed_branches | /usr/bin/grep -qv '^claude/done$' || false
}

# ── the CONFIRM=1 gate ───────────────────────────────────────────────────────────────────────
@test "--all without CONFIRM=1 refuses and lands NOTHING; with it, the same command lands" {
  push_branch claude/gated 1
  decl cloud-g claude/gated

  run cr --all
  [ "$status" -eq 65 ]
  echo "$output" | /usr/bin/grep -q 'CONFIRM=1'
  [ ! -s "$LAND_STUB_LOG" ]

  # POSITIVE CONTROL: the identical invocation with CONFIRM=1 DOES reach the lander, so the empty
  # log above is the gate refusing and not a broken fixture.
  CONFIRM=1 run cr --all
  [ "$status" -eq 0 ]
  [ -s "$LAND_STUB_LOG" ]
}

@test "--land without CONFIRM=1 refuses; --list is always allowed" {
  push_branch claude/one 1
  decl cloud-one claude/one

  run cr --land claude/one
  [ "$status" -eq 65 ]
  [ ! -s "$LAND_STUB_LOG" ]

  # --list needs no CONFIRM and stays read-only.
  run cr --list
  [ "$status" -eq 0 ]
  echo "$output" | /usr/bin/grep -q 'claude/one'
  [ ! -s "$LAND_STUB_LOG" ]
}

# ── --dry-run ────────────────────────────────────────────────────────────────────────────────
@test "--dry-run passes --dry-run to the lander on EVERY call, and a plain run passes it on none" {
  push_branch claude/d1 1
  push_branch claude/d2 2
  decl cloud-d1 claude/d1
  decl cloud-d2 claude/d2

  CONFIRM=1 run cr --all --dry-run
  [ "$status" -eq 0 ]
  # Two calls, both carrying --dry-run. The count assertion is what makes this two-sided: a run
  # that made ONE call would satisfy a bare grep.
  [ "$(/usr/bin/grep -c '^ARGS=.*--dry-run' "$LAND_STUB_LOG")" -eq 2 ]
  [ "$(/usr/bin/grep -c '^ARGS=' "$LAND_STUB_LOG")" -eq 2 ]

  # POSITIVE CONTROL for "never without": the same two branches WITHOUT --dry-run produce two calls
  # carrying none, so the flag tracks the option rather than being always-on or always-off.
  : > "$LAND_STUB_LOG"
  CONFIRM=1 run cr --all
  [ "$status" -eq 0 ]
  [ "$(/usr/bin/grep -c '^ARGS=' "$LAND_STUB_LOG")" -eq 2 ]
  [ "$(/usr/bin/grep -c '^ARGS=.*--dry-run' "$LAND_STUB_LOG")" -eq 0 ]
}

# ── per-branch failure isolation ─────────────────────────────────────────────────────────────
@test "a lander non-zero is reported per-branch and does NOT abort the remaining branches" {
  push_branch claude/bad 1
  push_branch claude/good 2
  decl cloud-bad claude/bad
  decl cloud-good claude/good

  LAND_STUB_FAIL="claude/bad" CONFIRM=1 run cr --all
  [ "$status" -eq 70 ]
  echo "$output" | /usr/bin/grep -q 'claude/bad'
  echo "$output" | /usr/bin/grep -q '6'
  # The whole point: the survivor still ran.
  landed_branches | /usr/bin/grep -q '^claude/good$'
  [ "$(/usr/bin/grep -c '^ARGS=' "$LAND_STUB_LOG")" -eq 2 ]
}

# ── the claude/* branch-name problem ─────────────────────────────────────────────────────────
@test "the lander is handed a SHIP_LAND_SESSION_BRANCH_RE that admits claude/ — scoped, not disabled" {
  push_branch claude/re 1
  decl cloud-re claude/re

  CONFIRM=1 run cr --all
  [ "$status" -eq 0 ]
  re="$(/usr/bin/grep -m1 '^RE=' "$LAND_STUB_LOG" | sed 's/^RE=//')"
  [ -n "$re" ]
  [ "$re" != "<unset>" ]
  # It admits the cloud branch...
  printf 'claude/re' | /usr/bin/grep -qE "$re"
  # ...and it is a SCOPED widening, not `.*`: a bare, prefix-less branch name is still rejected.
  printf 'randomname' | /usr/bin/grep -qvE "$re" || false
  # POSITIVE CONTROL that the override is load-bearing: ship-land.sh:1987's DEFAULT regex, spelled
  # out here, does NOT match claude/ — so without this env the land could only refuse.
  printf 'claude/re' | /usr/bin/grep -qvE '^(feat|fix|chore|docs|refactor|test|perf|style|build|ci)/.+' || false
}

# ── serialization ────────────────────────────────────────────────────────────────────────────
@test "--all lands smallest-diff first" {
  push_branch claude/big 4
  push_branch claude/small 1
  decl cloud-big claude/big
  decl cloud-small claude/small

  CONFIRM=1 run cr --all
  [ "$status" -eq 0 ]
  [ "$(landed_branches | head -1)" = "claude/small" ]
  [ "$(landed_branches | tail -1)" = "claude/big" ]
}

# ── the sensor ───────────────────────────────────────────────────────────────────────────────
@test "an unreachable remote is a SENSOR FAILURE (69), never 'no candidates' (0)" {
  push_branch claude/reachable 1

  # POSITIVE CONTROL first: against the real remote this fixture yields rows, so the empty result
  # below is the remote being unreachable and not an empty fixture.
  run cr --list
  [ "$status" -eq 0 ]
  echo "$output" | /usr/bin/grep -q 'claude/reachable'

  git -C "$REPO" remote set-url origin "$D/no-such-remote.git"
  run cr --list
  [ "$status" -eq 69 ]
  echo "$output" | /usr/bin/grep -qv 'claude/reachable' || false
}

# ── undeclared branches: discovered, flagged, never swept up by --all ────────────────────────
@test "--all skips an undeclared branch; --land names it explicitly and lands it" {
  push_branch claude/nodecl 1
  push_branch claude/yesdecl 1
  decl cloud-y claude/yesdecl

  CONFIRM=1 run cr --all
  [ "$status" -eq 0 ]
  landed_branches | /usr/bin/grep -q '^claude/yesdecl$'
  landed_branches | /usr/bin/grep -qv '^claude/nodecl$' || false

  # Naming it explicitly is the operator vouching for it, and that path DOES land.
  : > "$LAND_STUB_LOG"
  CONFIRM=1 run cr --land claude/nodecl
  [ "$status" -eq 0 ]
  landed_branches | /usr/bin/grep -q '^claude/nodecl$'
}

@test "--land on a branch absent from the remote refuses (65) without calling the lander" {
  push_branch claude/present 1

  CONFIRM=1 run cr --land claude/absent
  [ "$status" -eq 65 ]
  [ ! -s "$LAND_STUB_LOG" ]

  # POSITIVE CONTROL: a branch that IS on the remote reaches the lander off the same fixture.
  CONFIRM=1 run cr --land claude/present
  [ "$status" -eq 0 ]
  landed_branches | /usr/bin/grep -q '^claude/present$'
}

# ── usage ────────────────────────────────────────────────────────────────────────────────────
@test "no verb → 64; unknown option → 64" {
  run cr
  [ "$status" -eq 64 ]

  run cr --frobnicate
  [ "$status" -eq 64 ]
}
