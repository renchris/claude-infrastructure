#!/usr/bin/env bats
# cc-premise — a cited sha is ABSENT only when no repo the item could mean holds it.
#
# WHAT THIS FILE GUARDS, and it is a false POSITIVE, not a false negative. The sha arm gates on
# `own_repo` — the ITEM's project — and then resolves the item's cited shas against THIS checkout.
# Those are two different questions, and they come apart for the standing class of meta-items filed
# in claude-infrastructure ABOUT another project's work (cross-project standdown, dedupe, DROP).
# MEASURED (item cdbfe751ccc5, 2026-08-11): verdict=suspect on
# "CITED SHA d8329e766: no such object here (absent)" — a sha that is real, healthy, and an ancestor
# of origin/main in reso-management-app. The row was live work and the finding was fiction.
#
# EVERY REFUSAL HERE IS PAIRED WITH A CONVICTION, because "resolve it somewhere else first" sized
# wrong silences the arm outright, and an arm that reports nothing passes a suite that only asserts
# the negatives (memory: alarm-polarity-and-attention-budget). The pairs are: found-in-sibling
# stays silent / found-nowhere still convicts; an unaskable sibling concedes / an askable one that
# answers no does not; the widening disabled reproduces the OLD conviction, which is what proves
# the widening is the thing doing the work.
#
# The sibling set is fixtured end to end — its own conf file, its own throwaway checkouts. Pointing
# any of it at ~/Development would make these verdicts depend on what the operator happens to have
# cloned today (memory: unfixtured-sensor-executes-the-deployed-subject).

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CP="$REPO/bin/cc-premise"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  export CC_PREMISE_REPO=
  # The dispatch SSOT is fixtured by DEFAULT in this suite, and each test writes the rows it means.
  # Left unset, cc-premise would read the real scripts/dispatch-projects.conf and widen into the
  # operator's actual checkouts.
  export CC_DISPATCH_PROJECTS_CONF="$BATS_TEST_TMPDIR/projects.conf"
  : > "$CC_DISPATCH_PROJECTS_CONF"
  : > "$CC_BACKLOG_FILE"
}

refute_match() { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }

add() { printf '{"id":"%s","ts":"%s","event":"add","project":"claude-infrastructure","title":%s,"source":"t"}\n' \
          "$1" "${3:-2026-08-01T00:00:00Z}" "$(printf '%s' "$2" | jq -Rs .)" >> "$CC_BACKLOG_FILE"; }

verdict() { printf '%s' "$1" | sed -n 's/^verdict=//p'; }

# mkrepo <name> — a throwaway checkout with a real origin/main. Prints its path.
#
# THE DATES ARE PINNED, AND THAT IS LOAD-BEARING RATHER THAN TIDINESS. Unpinned, the commit sha is a
# function of the wall clock, so the token these tests cite changes every run — and a run whose sha
# happened to be un-citable (all-decimal, or a prefix of a fixture id) silently turned the headline
# control into a vacuous pass while its paired conviction went red. Observed live: two consecutive
# pre-fix runs of this file disagreed about which tests failed (memory: verification-harness-vacuous-
# pass-traps). Fixed dates + fixed identity + fixed tree ⇒ one constant sha, so the pair below either
# both hold or both fail, and neither can drift.
#
# The identity is passed with `git -c`, never written into the checkout's config: a `git -C "$var"
# config user.email` line is empty exactly when the path variable is, and `git -C ""` is a no-op that
# silently writes into the CURRENT repo (this repo's own validate-bash refuses the form for that
# reason — it re-authored 214 commits on 2026-08-05).
mkrepo() {
  local r="$BATS_TEST_TMPDIR/$1"
  mkdir -p "$r"
  printf '%s\n' "$1" > "$r/seed"
  git -C "$r" init -q -b main .
  git -C "$r" add -A
  GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" \
    git -c user.email=t@t -c user.name=t -C "$r" commit -qm "seed $1"
  git -C "$r" update-ref refs/remotes/origin/main HEAD
  printf '%s' "$r"
}

head_sha() { git -C "$1" rev-parse --short=9 HEAD; }

conf_row() { printf '%s %s\n' "$1" "$2" >> "$CC_DISPATCH_PROJECTS_CONF"; }

# ── the divergence: our item, their sha ──────────────────────────────────────────────────────────

@test "a claude-infrastructure item citing a SIBLING repo's sha is silent and stays clear" {
  # THE PRE-FIX CONTROL. Against unmodified origin/main this body emits
  # "CITED SHA <x>: no such object here (absent)" and verdict=suspect — the measured fiction on
  # cdbfe751ccc5, replayed with a sha that is genuinely healthy in a repo that is genuinely not
  # this one. Both assertions below fail there; that is the point of the arm.
  here="$(mkrepo here)"; there="$(mkrepo there)"
  export CC_PREMISE_REPO="$here"
  conf_row reso-management-app "repo=$there"
  sha="$(head_sha "$there")"

  # FIXTURE POSITIVE CONTROL. If this token were not a real object over there AND genuinely absent
  # here, the test would go green over a sha the arm never had reason to speak about. Its paired
  # conviction is the EXPLICIT-EMPTY test at the bottom, which cites the SAME constant sha.
  run git -C "$there" cat-file -t "$sha"
  [ "$status" -eq 0 ]
  run git -C "$here" cat-file -t "$sha"
  [ "$status" -ne 0 ]

  add 1111aaaa1111 "STAND DOWN — the reso commit $sha already landed there, close this as duplicate"
  run "$CP" check 1111aaaa1111
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  refute_match "$output" "CITED SHA"
  refute_match "$output" "CITED HEX TOKEN"
}

@test "a sha in NO repo at all still convicts — the widening is a miss handler, not a mute" {
  # The half that keeps the arm alive. A fix sized as "if it did not resolve, say nothing" would
  # pass the test above and delete the signal this arm exists for.
  here="$(mkrepo here)"; there="$(mkrepo there)"
  export CC_PREMISE_REPO="$here"
  conf_row reso-management-app "repo=$there"

  add 2222bbbb2222 "the commit deadbeef1 never landed anywhere"
  run "$CP" check 2222bbbb2222
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = suspect ]
  printf '%s' "$output" | grep -q "CITED SHA deadbeef1"
  # …and it now says how far it looked, which is the claim it is actually entitled to make.
  printf '%s' "$output" | grep -q "in no sibling checkout either"
  refute_match "$output" "NOT PROVEN ABSENT"
}

@test "an UNASKABLE sibling concedes instead of convicting — could-not-ask is not absent" {
  # The fabrication one level out. A declared checkout that is missing must not be read as "asked
  # and answered no": that is the same conflation `_git_usable` was built to stop, moved to the
  # sibling (memory: lookup-miss-is-not-absence). The line still prints — the pointer IS dead here
  # — but it concedes, and the verdict does not move.
  here="$(mkrepo here)"
  export CC_PREMISE_REPO="$here"
  conf_row reso-management-app "repo=$BATS_TEST_TMPDIR/no-such-checkout"

  add 3333cccc3333 "the commit deadbeef1 never landed anywhere"
  run "$CP" check 3333cccc3333
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  printf '%s' "$output" | grep -q "CITED SHA deadbeef1"
  printf '%s' "$output" | grep -q "NOT PROVEN ABSENT: reso-management-app could not be asked"
  refute_match "$output" "in no sibling checkout either"
}

@test "one PROVEN-absent sha still earns the verdict when another sha could not be asked" {
  # Per-sha honesty, not per-block. A body mixing the two must keep the conviction the provable
  # half earns — otherwise one unreadable sibling launders every dead pointer in the item.
  here="$(mkrepo here)"; there="$(mkrepo there)"
  export CC_PREMISE_REPO="$here"
  conf_row reso-management-app "repo=$there"
  conf_row doc_classifier "repo=$BATS_TEST_TMPDIR/no-such-checkout"

  add 4444dddd4444 "the commit deadbeef1 never landed anywhere"
  run "$CP" check 4444dddd4444
  [ "$status" -eq 0 ]
  # Every candidate must answer before absence is proven, and one of them cannot — so this one
  # concedes and holds the verdict. The conviction arm above is what pairs with it.
  [ "$(verdict "$output")" = clear ]
  printf '%s' "$output" | grep -q "NOT PROVEN ABSENT: doc_classifier could not be asked"
}

# ── the conf is read the way its two other consumers read it ─────────────────────────────────────

@test "a skip= row is not a checkout — it cannot rescue a sha, and cannot silence one" {
  # `skip=` declares a label with NO repo. Parsing it as a candidate would either crash or, worse,
  # widen into an empty path and manufacture a permanent could-not-ask for every item.
  here="$(mkrepo here)"
  export CC_PREMISE_REPO="$here"
  conf_row reso-qa-runner "skip=no open items"
  conf_row agent-secrets  "skip=secrets repo"

  add 5555eeee5555 "the commit deadbeef1 never landed anywhere"
  run "$CP" check 5555eeee5555
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = suspect ]
  refute_match "$output" "NOT PROVEN ABSENT"
}

@test "EXPLICIT-EMPTY conf disables the widening — and that reproduces the OLD conviction" {
  # The hermetic pin, and simultaneously the cleanest statement of what changed: the same item and
  # the same sibling checkout as the first test, with only the conf taken away, convicts again.
  here="$(mkrepo here)"; there="$(mkrepo there)"
  export CC_PREMISE_REPO="$here"
  export CC_DISPATCH_PROJECTS_CONF=
  sha="$(head_sha "$there")"

  add 6666ffff6666 "STAND DOWN — the reso commit $sha already landed there, close this as duplicate"
  run "$CP" check 6666ffff6666
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = suspect ]
  printf '%s' "$output" | grep -q "CITED SHA $sha"
  # …and the conviction may not claim a search that never happened. With no candidate set at all,
  # "in no sibling checkout either" is an overclaim, and it is invisible to a grep for the sha:
  # MEASURED 2026-08-23 (backlog 0d181d7b9925), this line was BYTE-IDENTICAL to the one the second
  # test asserts, where a real sibling was asked and answered no. That is the whole defect — the
  # clause carries zero information in exactly the case it was added to describe. Its pair is the
  # `grep -q` on line 119: one arm must say it, this one must not.
  refute_match "$output" "in no sibling checkout either"
}

@test "a comment and a trailing #comment on a repo= row parse the way cc-dispatch parses them" {
  here="$(mkrepo here)"; there="$(mkrepo there)"
  export CC_PREMISE_REPO="$here"
  printf '# a leading comment row\n\n' >> "$CC_DISPATCH_PROJECTS_CONF"
  conf_row reso-management-app "repo=$there   # verified 2026-07-29"
  sha="$(head_sha "$there")"

  add 7777aaaa7777 "STAND DOWN — the reso commit $sha already landed there"
  run "$CP" check 7777aaaa7777
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  refute_match "$output" "CITED SHA"
}

# ── the same divergence, one pointer kind over: CITED PATHS (backlog ee5472061246) ────────────────
#
# Fixing the sha arm alone left the SAME item minting the SAME fiction in a different sentence, and
# that is why these live beside the sha tests rather than in a file of their own. RE-MEASURED
# 2026-08-23, after 11b85f97b landed: cdbfe751ccc5 was still verdict=suspect, now on "CITED PATH(S)
# not at that location on origin/main: src/app, preview/bottle-service-tableside/layout.tsx" —
# where `src/app` is a live directory on reso-management-app's origin/main. Asked of every declared
# repo, that item's two paths land in two DIFFERENT states (one resolves in a sibling, one is
# absent everywhere), which is why the arm needs three states and not a boolean.
#
# EVERY REFUSAL HERE IS PAIRED WITH A CONVICTION, for the reason the header gives: a widening sized
# wrong silences the arm outright, and an arm that reports nothing passes a suite that only asserts
# the negatives (memory: alarm-polarity-and-attention-budget).

# addpath <repo> <path> — commit a file at <path> and advance origin/main.
#
# Dates pinned like `mkrepo`'s, for the same reason: an unpinned commit makes the tree's sha a
# function of the wall clock, and these repos are also cited BY sha elsewhere in this file.
addpath() {
  local r="$1" p="$2"
  mkdir -p "$r/$(dirname "$p")"
  printf 'x\n' > "$r/$p"
  git -C "$r" add -A
  GIT_AUTHOR_DATE="2026-01-02T00:00:00Z" GIT_COMMITTER_DATE="2026-01-02T00:00:00Z" \
    git -c user.email=t@t -c user.name=t -C "$r" commit -qm "add $p"
  git -C "$r" update-ref refs/remotes/origin/main HEAD
}

@test "a claude-infrastructure item citing a SIBLING repo's PATH is silent and stays clear" {
  # THE HEADLINE, and verbatim the shape of the live exhibit: our item, their file.
  here="$(mkrepo here)"; there="$(mkrepo there)"
  addpath "$there" src/app/page.tsx
  export CC_PREMISE_REPO="$here"
  conf_row reso-management-app "repo=$there"

  add aaaa1111aaaa "STAND DOWN — src/app/page.tsx is reso's work, close this as a duplicate"
  run "$CP" check aaaa1111aaaa
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  refute_match "$output" "CITED PATH"
}

@test "a path in NO repo at all still convicts — and now says how far it looked" {
  # THE PAIRED CONVICTION. Without this half the fix could equally have been "delete the arm", and
  # a suite asserting only the silence would go green on a sensor that reports nothing at all
  # (memory: per-site-mutation-attributes-coverage). The scope clause is the half that is new:
  # pre-fix this convicted too, but could not say it had asked anyone else.
  here="$(mkrepo here)"; there="$(mkrepo there)"
  export CC_PREMISE_REPO="$here"
  conf_row reso-management-app "repo=$there"

  add bbbb2222bbbb "fix src/app/page.tsx — it is red"
  run "$CP" check bbbb2222bbbb
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = suspect ]
  printf '%s' "$output" | grep -q "in no sibling checkout either"
  refute_match "$output" "NOT PROVEN ABSENT"
}

@test "an UNASKABLE sibling concedes instead of convicting a PATH — could-not-ask is not absent" {
  # A declared repo whose checkout is missing is kept as a CANDIDATE on purpose (see
  # `_sibling_repos`): dropping it here would let a vanished sibling read as "asked and answered
  # no", which is the same fabrication one level out.
  here="$(mkrepo here)"
  export CC_PREMISE_REPO="$here"
  conf_row reso-management-app "repo=$BATS_TEST_TMPDIR/never-cloned"

  add cccc3333cccc "fix src/app/page.tsx — it is red"
  run "$CP" check cccc3333cccc
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  printf '%s' "$output" | grep -q "NOT PROVEN ABSENT"
}

@test "a sibling with NO origin/main is UNASKABLE for a path, though its objects are readable" {
  # THE SECOND CONTROL, and the one site that separates `_repo_trunk_usable` from `_repo_usable`.
  # A sha is an OBJECT and resolves with no ref at all, so the sha arm's control is `--git-dir`. A
  # PATH is only meaningful relative to a commit, and this arm asks `origin/main:<path>` — so a
  # perfectly readable checkout that simply has no origin/main answers every path query with a
  # miss. Reusing the object control here would call this repo ASKABLE, take that miss as an
  # answer, and convict: `verdict=suspect` with no concession, which is what this test would then
  # read. It is the mutant that attributes the second control to a site of its own.
  here="$(mkrepo here)"
  notrunk="$BATS_TEST_TMPDIR/notrunk"; mkdir -p "$notrunk"
  printf 'seed\n' > "$notrunk/seed"
  git -C "$notrunk" init -q -b main .
  git -C "$notrunk" add -A
  GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" \
    git -c user.email=t@t -c user.name=t -C "$notrunk" commit -qm "seed notrunk"
  # …and deliberately NO `update-ref refs/remotes/origin/main`. That absence IS the fixture.
  [ "$(git -C "$notrunk" rev-parse --verify --quiet origin/main | wc -l | tr -d ' ')" -eq 0 ]
  export CC_PREMISE_REPO="$here"
  conf_row reso-management-app "repo=$notrunk"

  add dddd4444dddd "fix src/app/page.tsx — it is red"
  run "$CP" check dddd4444dddd
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  printf '%s' "$output" | grep -q "NOT PROVEN ABSENT"
}

@test "EXPLICIT-EMPTY conf disables the PATH widening — and that reproduces the OLD conviction" {
  # The hermetic pin, and simultaneously the cleanest statement of what changed: the same item and
  # the same sibling checkout as the headline test, with only the conf taken away, convicts again.
  # This one holds BOTH before and after the fix — that is its job. It is the base case, so a
  # widening that quietly swallowed every path finding would red here.
  here="$(mkrepo here)"; there="$(mkrepo there)"
  addpath "$there" src/app/page.tsx
  export CC_PREMISE_REPO="$here"
  export CC_DISPATCH_PROJECTS_CONF=

  add eeee5555eeee "STAND DOWN — src/app/page.tsx is reso's work, close this as a duplicate"
  run "$CP" check eeee5555eeee
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = suspect ]
  printf '%s' "$output" | grep -q "src/app/page.tsx"
  refute_match "$output" "in no sibling checkout either"
}
