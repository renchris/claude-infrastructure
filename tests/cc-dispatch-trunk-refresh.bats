#!/usr/bin/env bats
# cc-dispatch — refresh_trunk: the admission gate reads a ref, and something must refresh it.
#
# WHAT THIS IS ABOUT. `cc-backlog claim --venue cloud` consults bin/cc-eligible's park arm, whose
# whole subject is a file a PREVIOUS CLOUD DISPATCH pushed to GitHub — `docs/parks/<id>.md`. The arm
# reads it off the LOCAL remote-tracking ref, deliberately (scripts/cloud-park.sh: "the park is NOT
# in effect until this file is on trunk"). So the writer is a remote push and the reader is a local
# ref, and until this change NOTHING in the dispatch path connected them: bin/cc-eligible and
# bin/cc-backlog contain no `fetch` at all, and cc-dispatch's only two are inside warm_worktree and
# the wcwd freshness probe, both under `if [ "$venue" != cloud ]` — while the live dispatcher runs
# CC_DISPATCH_VENUE_ONLY=cloud. The ref was refreshed only by arms with no ordering relation to the
# park's landing (postland-verify, stranded-sweep, cloud-return, a hand `git pull`).
#
# WHY THE EXISTING PARK SUITE CANNOT SEE THIS, which is the reason for a separate file rather than a
# case in tests/cc-eligible-park.bats. That suite's `sync_trunk` is `git update-ref
# refs/remotes/origin/main <local sha>` — one repo, no remote, no fetch. It is the right fixture for
# the questions it asks (does the arm honour trunk? does the desk record retract it?) and it CANNOT
# exhibit this one by construction: staleness only exists where a second machine can move the trunk
# without the reader hearing. These cases therefore use a real bare remote and two real clones — the
# production topology — and the variable under test is a `git fetch`, nothing else.
#
# THE FIRST TWO CASES ARE THE MEASUREMENT, not a regression pin: they establish that a stale ref does
# not make the gate ABSTAIN, it makes it ASSERT `park : none` and admit. A reader that reports its
# own uncertainty would have cost one dispatch; this cost backlog 485f8f87eb5f a seventh.
#
# RED-PROOF, MEASURED rather than asserted (re-runnable: `git archive origin/main | tar -x` into a
# scratch tree, copy this file into its tests/, run it there). Against the pristine trunk file the
# suite reads 3 ok / 5 RED:
#
#   GREEN 1, 2, 3 — and this is CORRECT, not a weak pin. They characterise bin/cc-eligible, which
#                   this change does not touch, and they are the MEASUREMENT that motivates it: the
#                   defect they describe is a property of trunk, so a suite in which they went red
#                   would be claiming the bug did not exist before the fix.
#   RED   4-8     — every case whose subject is refresh_trunk, which pristine does not define; the
#                   probe emits NO-SUCH-FUNCTION rather than running an empty library, so these fail
#                   loudly instead of passing vacuously. Case 8 also pins the `gate=trunk-unrefreshed`
#                   token by grepping the shipped file, so it is red on both halves.
#
# Assertions use the explicit `|| { …; false; }` form: a non-final `[[ ]]` is errexit-EXEMPT under
# bats and would be a DEAD assertion that can never fail.

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CE="$REPO/bin/cc-eligible"
  CB="$REPO/bin/cc-backlog"
  CD="$REPO/bin/cc-dispatch"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/.dispatch-kick"
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/no-such-dispatch"
  printf '#!/bin/bash\necho "[]"\n' > "$BATS_TEST_TMPDIR/nosess"; chmod +x "$BATS_TEST_TMPDIR/nosess"
  export CC_BACKLOG_SESSIONS_BIN="$BATS_TEST_TMPDIR/nosess"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  REMOTE="$BATS_TEST_TMPDIR/remote.git"
  G="$HOME/Development/probe"          # the DESK clone — what repo_for("probe") resolves to
  VM="$BATS_TEST_TMPDIR/vm"            # a second clone — stands in for the cloud worker
  STAMP="2026-08-31T21:53:11Z"
}

# mkremote → a bare remote plus a desk clone with `origin/main` genuinely tracking it.
mkremote() {
  git init -q --bare "$REMOTE"
  mkdir -p "$(dirname "$G")"
  git init -q -b main "$G"
  # THE ARGUMENT IS ASSERTED, not the chain (tests/cc-eligible-park.bats's mkrepo, same reason).
  # `git -C ""` is a documented NO-OP, so an empty $G would write this fixture identity into
  # whatever repo the process is standing in — and the worktrees on this box share one .git/config.
  git -C "${G:?repo path required}" config user.email t@e.com
  git -C "${G:?repo path required}" config user.name t
  echo seed > "$G/f1"; git -C "$G" add f1; git -C "$G" commit -qm c1
  git -C "$G" remote add origin "$REMOTE"
  git -C "$G" push -q -u origin main
}

# vm_lands_park <id> → the OTHER clone pushes a well-formed park to the real trunk. The desk clone is
# NOT fetched: that is the whole point, and every case says explicitly when it fetches.
vm_lands_park() {
  git clone -q "$REMOTE" "$VM"
  git -C "${VM:?clone path required}" config user.email t@e.com
  git -C "${VM:?clone path required}" config user.name t
  git -C "$VM" checkout -q -B main origin/main
  mkdir -p "$VM/docs/parks"
  { printf '# park log — cc-backlog %s\n\nAPPEND ONLY.\n\n' "$1"
    printf '## %s\n\n' "$STAMP"
    printf 'branch: claude/fire-fixture-1\n'
    printf 'needs: dispatch on-box (a Mac with ~/Development/reso-management-app)\n\n'
  } > "$VM/docs/parks/$1.md"
  git -C "$VM" add docs; git -C "$VM" commit -qm "park $1"; git -C "$VM" push -q origin main
}

add() { "$CB" add --title "$2" --project probe --source "$1"; }

# ── the measurement: what a stale ref does to the gate ──────────────────────────────────────────

@test "STALE: a park that IS on the real trunk is invisible, and the gate ADMITS" {
  mkremote
  local id; id="$(add trunkref-stale "make the widget green")"
  vm_lands_park "$id"
  # ground truth: the park is on the trunk the desk's origin points AT
  git --git-dir="$REMOTE" show "main:docs/parks/$id.md" >/dev/null 2>&1 \
    || { echo "fixture broken: park not on the remote"; false; }
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
}

@test "STALE: the gate does not abstain — it ASSERTS 'no park on trunk'" {
  # The expensive half. `not-measured` would have been a true statement about a ref of unknown age;
  # `none` is a positive claim of absence made over a ref nothing refreshed. bin/cc-eligible's own
  # doctrine is "exit 0 with a verdict that NAMES the uncertainty", and this is the site that did not.
  mkremote
  local id; id="$(add trunkref-assert "make the widget green")"
  vm_lands_park "$id"
  run "$CE" why "$id"
  [[ "$output" == *"park"*"none"* ]] \
    || { echo "expected a positive 'none' claim: $output"; false; }
}

@test "FETCH IS THE ONLY VARIABLE: one fetch turns the same call into ineligible-parked" {
  # Same repo, same item, same park, same ledger. If this case and the first ever disagree about
  # anything else, the pair has stopped isolating the fetch.
  mkremote
  local id; id="$(add trunkref-fetched "make the widget green")"
  vm_lands_park "$id"
  git -C "$G" fetch origin -q
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-parked"* ]] || { echo "$output"; false; }
  [[ "$output" == *"reso-management-app"* ]] \
    || { echo "the refusal dropped the operator step: $output"; false; }
}

# ── refresh_trunk itself ────────────────────────────────────────────────────────────────────────

# probe <body> → run <body> against the helpers EXTRACTED FROM the shipped bin/cc-dispatch, which is
# this repo's idiom for exercising one of its functions (tests/cc-dispatch-venue.bats setup) and is
# what makes these cases replay the real artifact rather than a hand-typed approximation of it
# (memory: control-must-replay-the-real-artifact). cc-dispatch has no source-only guard — sourcing it
# runs a dispatch pass — so extraction is the only way in.
#
# `NO-SUCH-FUNCTION` is emitted rather than silently skipped: against a pristine trunk the sed finds
# nothing, and a suite that quietly ran an empty library would report green for a missing feature.
probe() {
  local lib="$BATS_TEST_TMPDIR/lib.sh"
  { echo "NL='"; echo "'"
    echo 'PROJECTS_CONF="${PROJECTS_CONF:-/nonexistent}"'
    sed -n '/^TRUNK_REFRESH_OK=/p;/^TRUNK_REFRESH_BAD=/p' "$CD"
    sed -n '/^conf_repo()/,/^}/p'     "$CD"
    sed -n '/^project_repo()/,/^}/p'  "$CD"
    sed -n '/^refresh_trunk()/,/^}/p' "$CD"
  } > "$lib"
  bash -c '
    set -uo pipefail
    . "$1" || exit 9
    type refresh_trunk >/dev/null 2>&1 || { echo "NO-SUCH-FUNCTION"; exit 9; }
    shift
    eval "$@"
  ' _ "$lib" "$1"
}

@test "refresh_trunk: a project whose repo tracks a remote comes back current" {
  mkremote
  local id; id="$(add trunkref-fn "make the widget green")"
  vm_lands_park "$id"
  run probe 'PROJECT=probe; refresh_trunk probe && git -C "$HOME/Development/probe" show origin/main:docs/parks/'"$id"'.md >/dev/null 2>&1 && echo VISIBLE'
  [[ "$output" != *NO-SUCH-FUNCTION* ]] || { echo "refresh_trunk is not defined"; false; }
  [[ "$output" == *VISIBLE* ]] \
    || { echo "the park stayed invisible after refresh_trunk: $output"; false; }
}

@test "refresh_trunk: ONE fetch per project per pass, not one per claim" {
  # A wave of N cloud rows in one project must cost one fetch. Counted by shimming git on PATH.
  mkremote
  mkdir -p "$BATS_TEST_TMPDIR/shim"
  # The real git is resolved ONCE, by absolute path, so the shim cannot recurse into itself when it
  # is first on PATH.
  local realgit; realgit="$(command -v git)"
  { echo '#!/bin/bash'
    echo 'case " $* " in *" fetch "*) echo x >> "$COUNTF" ;; esac'
    echo "exec '$realgit' \"\$@\""
  } > "$BATS_TEST_TMPDIR/shim/git"
  chmod +x "$BATS_TEST_TMPDIR/shim/git"
  export COUNTF="$BATS_TEST_TMPDIR/fetches"; : > "$COUNTF"
  run probe 'PROJECT=probe; PATH="'"$BATS_TEST_TMPDIR"'/shim:$PATH"; refresh_trunk probe; refresh_trunk probe; refresh_trunk probe; echo done'
  [[ "$output" == *done* ]] || { echo "$output"; false; }
  [ "$(wc -l < "$COUNTF")" -eq 1 ] \
    || { echo "expected exactly 1 fetch across 3 calls, got $(wc -l < "$COUNTF")"; false; }
}

@test "refresh_trunk: the memo is PER PROJECT — a bad repo does not convict its neighbour" {
  # The bug a single cached rc would have: one unreachable project poisons every project after it.
  mkremote
  run probe 'PROJECT=probe; refresh_trunk nosuchproject; bad=$?; refresh_trunk probe; good=$?; echo "bad=$bad good=$good"'
  [[ "$output" == *"bad=1"* ]] || { echo "an absent repo should fail: $output"; false; }
  [[ "$output" == *"good=0"* ]] || { echo "a good repo was convicted by its neighbour: $output"; false; }
}

@test "refresh_trunk: CC_DISPATCH_TRUNK_REFRESH=off restores the incumbent exactly" {
  mkremote
  local id; id="$(add trunkref-off "make the widget green")"
  vm_lands_park "$id"
  run probe 'PROJECT=probe; CC_DISPATCH_TRUNK_REFRESH=off refresh_trunk probe; echo "rc=$?"; git -C "$HOME/Development/probe" show origin/main:docs/parks/'"$id"'.md >/dev/null 2>&1 && echo VISIBLE || echo INVISIBLE'
  [[ "$output" == *"rc=0"* ]] || { echo "the kill switch must fail open: $output"; false; }
  [[ "$output" == *INVISIBLE* ]] \
    || { echo "the kill switch did not actually suppress the fetch: $output"; false; }
}

@test "FAIL-OPEN: an unfetchable repo does not starve the queue, and says so" {
  # I6 — a sensor failure must never block a fire. But silence is what made this expensive, so the
  # non-measurement has to be indexable: `gate=trunk-unrefreshed` is the machine token, matched
  # verbatim the way claim_gate_skip matches its own.
  grep -qF 'gate=trunk-unrefreshed' "$CD" \
    || { echo "the fail-open path records no machine token"; false; }
  run probe 'PROJECT=probe; refresh_trunk nosuchproject; echo "rc=$?"'
  [[ "$output" == *"rc=1"* ]] \
    || { echo "an unfetchable repo must report rc 1 so the call site can journal it: $output"; false; }
}
